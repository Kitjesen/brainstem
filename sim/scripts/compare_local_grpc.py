"""
逐帧对比 local ONNX vs gRPC brainstem 的输入输出。
同一个 MuJoCo 物理状态，两边各自算 obs / 推理 / 得到 action，打印差异。

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
from scipy.spatial.transform import Rotation as R
from collections import deque

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

NAMES_57 = (
    ['gyro_x','gyro_y','gyro_z','grav_x','grav_y','grav_z','cmd_vx','cmd_vy','cmd_vyaw'] +
    [f'jpos_{i}' for i in range(16)] +
    [f'jvel_{i}' for i in range(16)] +
    [f'act_{i}' for i in range(16)]
)
NAMES_16 = [
    'fr_hip','fr_thigh','fr_calf','fl_hip','fl_thigh','fl_calf',
    'rr_hip','rr_thigh','rr_calf','rl_hip','rl_thigh','rl_calf',
    'fr_foot','fl_foot','rr_foot','rl_foot'
]


def local_obs(data, vx, vy, vyaw, last_action):
    """和 walk_ref.py 100% 一致。"""
    q = data.qpos[dof_ids].astype(np.double) - default_angle
    dq = data.qvel[dof_vel].astype(np.double) * 0.05
    q[-4:] = 0.0
    imu_quat = data.sensor('orientation').data[[1,2,3,0]].astype(np.double)
    r_imu = R.from_quat(imu_quat)
    proj = r_imu.apply([0.,0.,-1.], inverse=True).astype(np.double)
    gyro_local = data.sensor('angular-velocity').data.astype(np.double)
    base_quat = data.qpos[3:7][[1,2,3,0]].astype(np.double)
    r_base = R.from_quat(base_quat)
    gyro = r_base.apply(r_imu.apply(gyro_local), inverse=True) * 0.25
    return np.concatenate([gyro, proj, [vx,vy,vyaw], q, dq, last_action]).astype(np.float32)


def build_sim_state(data, elapsed_s):
    """发给 Dart server 的 SimState（不取共轭）。"""
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


def dart_obs_from_history(h):
    """从 History 反推当前帧 obs（57维）。"""
    gyro = np.array([h.gyroscope.x, h.gyroscope.y, h.gyroscope.z]) * 0.25
    grav = np.array([h.projected_gravity.x, h.projected_gravity.y, h.projected_gravity.z])
    cmd = np.zeros(3)
    if h.command.HasField('walk'):
        cmd = np.array([h.command.walk.x, h.command.walk.y, h.command.walk.z])
    jpos = np.array(h.joint_position.values) - default_angle
    jpos[-4:] = 0.0
    jvel = np.array(h.joint_velocity.values) * 0.05
    act_scale = np.array([0.125,0.25,0.25]*4 + [5,5,5,5])
    act = (np.array(h.action.values) - default_angle) / act_scale
    return np.concatenate([gyro, grav, cmd, jpos, jvel, act]).astype(np.float32)


def main():
    # ── gRPC ──────────────────────────────────────────────────
    print("Connecting to brainstem...")
    channel = grpc.insecure_channel("127.0.0.1:13145")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)
    print(f"Connected. CMS: {stub.GetCmsState(msg.Empty()).kind}")

    # ── Local ONNX ────────────────────────────────────────────
    sess = ort.InferenceSession("sim/model/policy_v9_800.onnx")
    input_name = sess.get_inputs()[0].name
    print(f"ONNX: {input_name}")

    # ── MuJoCo ────────────────────────────────────────────────
    model = mujoco.MjModel.from_xml_path("sim/robot/quadruped_v3.xml")
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)

    data.qpos[:3] = [0,0,0.5]; data.qpos[3:7] = [1,0,0,0]
    data.qpos[dof_ids] = default_angle.copy(); data.qvel[:] = 0
    mujoco.mj_step(model, data)

    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15,15,20]*4, dtype=np.float64)
    target_q = default_angle.copy()

    # Local state
    local_last_action = np.zeros(16, dtype=np.float32)
    local_history = deque(maxlen=5)

    # StandUp via gRPC
    try:
        stub.StandUp(msg.Empty())
    except:
        pass

    count = 0
    decimation = 4

    # Walk at step 150
    walk_sent = False

    print("\n=== Running 300 steps (6s): warmup 150 + walk 150 ===\n")

    for step in range(300):
        now_s = count * 0.005

        if step == 150:
            try:
                stub.Walk(msg.Vector3(x=0.3, y=0.0, z=0.0))
                walk_sent = True
                print(f"  [{now_s:.1f}s] >>> Walk(0.3,0,0) sent\n")
            except:
                pass

        if count % decimation == 0:
            cmd_vx = 0.3 if walk_sent else 0.0

            # === LOCAL obs ===
            py_obs = local_obs(data, cmd_vx, 0, 0, local_last_action)
            local_history.append(py_obs.copy())
            while len(local_history) < 5:
                local_history.appendleft(py_obs.copy())
            py_flat = np.concatenate(list(local_history)).astype(np.float32).reshape(1,-1)
            py_raw = sess.run(None, {input_name: py_flat})[0].squeeze()

            # Local target
            if step > 100:
                py_scaled = np.zeros(16)
                for j in range(4):
                    b=j*3
                    py_scaled[b]=py_raw[b]*0.125; py_scaled[b+1]=py_raw[b+1]*0.25; py_scaled[b+2]=py_raw[b+2]*0.25
                py_scaled[12:]=py_raw[12:]*5.0
                py_target = py_scaled + default_angle
                local_last_action = py_raw.astype(np.float32).copy()
            else:
                py_target = default_angle.copy()
                local_last_action = py_raw.astype(np.float32).copy()

            # === GRPC obs + action ===
            sim_state = build_sim_state(data, now_s)
            stub.Step(sim_state)
            history = stub.Tick(msg.Empty())
            dart_target = np.array(history.next_action.values, dtype=np.float64)
            dart_obs = dart_obs_from_history(history)

            # === 对比 obs (当前帧) ===
            obs_diff = np.abs(py_obs - dart_obs)
            max_obs_diff = np.max(obs_diff)
            max_obs_idx = np.argmax(obs_diff)

            # === 对比 action (target_q) ===
            act_diff = np.abs(py_target - dart_target)
            max_act_diff = np.max(act_diff)
            max_act_idx = np.argmax(act_diff)

            # 打印
            if step % 25 == 0 or max_obs_diff > 0.1 or max_act_diff > 0.1:
                z = float(data.qpos[2])
                print(f"--- step {step} [{now_s:.2f}s] z={z:.3f} ---")
                print(f"  OBS max_diff={max_obs_diff:.4f} @ {NAMES_57[max_obs_idx]}")
                if max_obs_diff > 0.01:
                    bad = np.where(obs_diff > 0.01)[0]
                    for idx in bad[:8]:
                        print(f"    [{idx:2d}] {NAMES_57[idx]:8s}  local={py_obs[idx]:+.4f}  dart={dart_obs[idx]:+.4f}  diff={obs_diff[idx]:.4f}")
                print(f"  ACT max_diff={max_act_diff:.4f} @ {NAMES_16[max_act_idx]}")
                if max_act_diff > 0.01:
                    bad_a = np.where(act_diff > 0.01)[0]
                    for idx in bad_a[:8]:
                        print(f"    [{idx:2d}] {NAMES_16[idx]:12s}  local={py_target[idx]:+.4f}  dart={dart_target[idx]:+.4f}  diff={act_diff[idx]:.4f}")
                print()

        # PD（用 local target 驱动物理）
        for _ in range(decimation):
            q = data.qpos[dof_ids]; dq = data.qvel[dof_vel]
            tau = np.zeros(16)
            tau[:12] = kp*(py_target[:12]-q[:12]) - kd*dq[:12]
            tau[12:] = 1.0*(py_target[12:]-dq[12:])
            data.ctrl[:] = np.clip(tau, -100, 100)
            mujoco.mj_step(model, data)
            count += 1

    print("Done.")
    channel.close()


if __name__ == "__main__":
    main()
