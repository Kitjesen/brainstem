"""
Legacy server gRPC 测试。兼容 legacy SimDogServer（没有 GetCmsState）。
和 walk_ref.py 相同的物理循环，推理走 legacy Dart server。

用法:
    # 终端 1: legacy server (sim_thunder.dart)
    # 终端 2: python sim/scripts/walk_legacy.py --vx 0.3 --duration 10
"""
import math
import numpy as np
import mujoco
import grpc
import argparse, sys, time
from pathlib import Path
from scipy.spatial.transform import Rotation as R

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


def build_sim_state(data, elapsed_s):
    """和 legacy sim_dog.dart step() 对齐：四元数不取共轭。"""
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


def dart_to_mj(d):
    mj = np.zeros(16)
    for leg in range(4):
        dd, m = leg*3, leg*4
        mj[m]=d[dd]; mj[m+1]=d[dd+1]; mj[m+2]=d[dd+2]; mj[m+3]=d[12+leg]
    return mj


def run(args):
    print(f"Connecting to {args.host}:{args.port}...")
    channel = grpc.insecure_channel(f"{args.host}:{args.port}")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)
    print("Connected.")

    model = mujoco.MjModel.from_xml_path(args.xml)
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    decimation = 4
    dt = 0.005

    data.qpos[:3] = [0, 0, 0.5]
    data.qpos[3:7] = [1, 0, 0, 0]
    data.qpos[dof_ids] = default_angle.copy()
    data.qvel[:] = 0
    mujoco.mj_step(model, data)

    target_q = default_angle.copy()
    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15,15,20]*4, dtype=np.float64)

    # StandUp
    stub.StandUp(msg.Empty())
    standup_done = False
    walk_sent = False
    count = 0
    sim_steps = int(args.duration / dt)

    print(f"Running {sim_steps} steps ({args.duration}s)")

    for i in range(sim_steps):
        now_s = count * dt

        if count % decimation == 0:
            sim_state = build_sim_state(data, now_s)
            stub.Step(sim_state)

            history = stub.Tick(msg.Empty())
            target_q = np.array(history.next_action.values, dtype=np.float64)

            if len(history.kp.values) == 16:
                kp = np.array(history.kp.values[:12], dtype=np.float64)
            if len(history.kd.values) == 16:
                kd = np.array(history.kd.values[:12], dtype=np.float64)

            # 3秒后发 Walk
            if not walk_sent and now_s >= 3.0:
                stub.Walk(msg.Vector3(x=args.vx, y=args.vy, z=args.vyaw))
                walk_sent = True
                print(f"  [{now_s:.1f}s] Walk({args.vx},{args.vy},{args.vyaw}) sent")

        # PD 每步算
        q = data.qpos[dof_ids].astype(np.float64)
        dq = data.qvel[dof_vel].astype(np.float64)
        tau = np.zeros(16)
        tau[:12] = kp * (target_q[:12] - q[:12]) - kd * dq[:12]
        tau[12:] = 1.0 * (target_q[12:] - dq[12:])
        data.ctrl[:] = np.clip(tau, -100, 100)

        mujoco.mj_step(model, data)
        count += 1

        if count % int(1.0 / dt) == 0:
            x, y, z = data.qpos[0], data.qpos[1], data.qpos[2]
            mode = "WALK" if walk_sent else "STANDUP"
            print(f"  [{now_s:.1f}s] pos=({x:.3f}, {y:.3f}, {z:.3f}) {mode}")

    x, y = data.qpos[0], data.qpos[1]
    print(f"\nFinal: x={x:.3f} y={y:.3f} disp={math.sqrt(x**2+y**2):.3f}")
    channel.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=13145)
    parser.add_argument("--xml", default="sim/robot/quadruped_v3.xml")
    parser.add_argument("--vx", type=float, default=0.3)
    parser.add_argument("--vy", type=float, default=0.0)
    parser.add_argument("--vyaw", type=float, default=0.0)
    parser.add_argument("--duration", type=float, default=10.0)
    args = parser.parse_args()
    run(args)
