"""
精确对比：用 Dart 返回的 285 维 obs buffer 跑本地 ONNX，对比 nextAction。

Dart 通过 History.observation 返回内部的 ONNX 输入 buffer（仅 Walking 时有值），
Python 用同一个 buffer 跑本地 ONNX，如果输出一致则证明链路完全正确。

用法:
    # 终端 1: dart run han_dog/bin/server.dart
    # 终端 2: python sim/scripts/compare_local_grpc.py
"""
import numpy as np
import mujoco
import onnxruntime as ort
import grpc
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROTO_PY_ROOT = SCRIPT_DIR.parent.parent / "han_dog_message" / "python"
if str(PROTO_PY_ROOT) not in sys.path:
    sys.path.insert(0, str(PROTO_PY_ROOT))
import han_dog_message as msg

dof_ids = [7,8,9, 11,12,13, 15,16,17, 19,20,21, 10,14,18,22]
dof_vel = [6,7,8, 10,11,12, 14,15,16, 18,19,20, 9,13,17,21]
default_angle = np.array([
    -0.1,-0.8,1.8, 0.1,0.8,-1.8, 0.1,0.8,-1.8, -0.1,-0.8,1.8, 0,0,0,0
], dtype=np.double)
AS = np.array([0.125,0.25,0.25]*4+[5,5,5,5])
NAMES_16 = [
    'fr_hip','fr_thigh','fr_calf','fl_hip','fl_thigh','fl_calf',
    'rr_hip','rr_thigh','rr_calf','rl_hip','rl_thigh','rl_calf',
    'fr_foot','fl_foot','rr_foot','rl_foot'
]


def build_sim_state(data, elapsed_s):
    raw_q = data.sensor('orientation').data
    gyro = data.sensor('angular-velocity').data
    jp = [float(data.qpos[i]) for i in dof_ids]
    jv = [float(data.qvel[i]) for i in dof_vel]
    s = int(elapsed_s); n = int((elapsed_s - s) * 1e9)
    return msg.SimState(
        gyroscope=msg.Vector3(x=float(gyro[0]), y=float(gyro[1]), z=float(gyro[2])),
        quaternion=msg.Quaternion(w=float(raw_q[0]), x=float(raw_q[1]),
                                  y=float(raw_q[2]), z=float(raw_q[3])),
        joint_position=msg.Matrix4(values=jp),
        joint_velocity=msg.Matrix4(values=jv),
        timestamp=msg.Duration(seconds=s, nanos=n),
    )


def main():
    print("Connecting to brainstem...")
    channel = grpc.insecure_channel("127.0.0.1:13145")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)

    sess = ort.InferenceSession("model/policy_260106.onnx")
    input_name = sess.get_inputs()[0].name
    print(f"ONNX: {input_name}")

    model = mujoco.MjModel.from_xml_path("sim/robot/quadruped_v3.xml")
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    data.qpos[:3] = [0,0,0.5]; data.qpos[3:7] = [1,0,0,0]
    data.qpos[dof_ids] = default_angle.copy(); data.qvel[:] = 0
    mujoco.mj_step(model, data)

    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15,15,20]*4, dtype=np.float64)
    target_q = default_angle.copy()
    count = 0; decimation = 4
    walk_sent = False; walk_tick = 0

    stub.StandUp(msg.Empty())

    print("\n=== StandUp 3.5s + Walk 2.5s ===\n")

    for i in range(1200):
        now_s = count * 0.005

        if count % decimation == 0:
            sim_state = build_sim_state(data, now_s)
            stub.Step(sim_state)

            if not walk_sent and now_s >= 3.5:
                stub.Walk(msg.Vector3(x=0.3, y=0.0, z=0.0))
                walk_sent = True
                print(f"  [{now_s:.1f}s] Walk sent\n")

            history = stub.Tick(msg.Empty())
            dart_target = np.array(history.next_action.values, dtype=np.float64)
            if len(history.kp.values) == 16:
                kp = np.array(history.kp.values[:12])
            if len(history.kd.values) == 16:
                kd = np.array(history.kd.values[:12])
            target_q = dart_target

            # 用 Dart 返回的 285 维 obs buffer 跑本地 ONNX
            dart_obs = list(history.observation)
            if walk_sent and len(dart_obs) == 285:
                walk_tick += 1
                if walk_tick <= 20:
                    # 同一个 buffer → 本地 ONNX
                    local_input = np.array(dart_obs, dtype=np.float32).reshape(1, -1)
                    local_raw = sess.run(None, {input_name: local_input})[0].squeeze()
                    lsc = np.zeros(16)
                    for j in range(4):
                        b = j*3
                        lsc[b] = local_raw[b]*0.125
                        lsc[b+1] = local_raw[b+1]*0.25
                        lsc[b+2] = local_raw[b+2]*0.25
                    lsc[12:] = local_raw[12:]*5.0
                    local_target = lsc + default_angle

                    diff = np.abs(dart_target - local_target)
                    max_diff = diff.max()
                    max_idx = np.argmax(diff)
                    print(f"  [{now_s:.2f}s] tick#{walk_tick:2d} "
                          f"legs={diff[:12].max():.10f} wheels={diff[12:].max():.10f} "
                          f"max={max_diff:.10f} @ {NAMES_16[max_idx]}")

        q = data.qpos[dof_ids]; dq = data.qvel[dof_vel]
        tau = np.zeros(16)
        tau[:12] = kp*(target_q[:12]-q[:12]) - kd*dq[:12]
        tau[12:] = 1.0*(target_q[12:]-dq[12:])
        data.ctrl[:] = np.clip(tau, -100, 100)
        mujoco.mj_step(model, data)
        count += 1

    print(f"\nFinal: x={data.qpos[0]:.3f}")
    channel.close()


if __name__ == "__main__":
    main()
