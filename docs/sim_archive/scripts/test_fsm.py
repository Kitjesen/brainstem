"""
完整 FSM 测试：Grounded → StandUp → Walk → StandUp → SitDown → Grounded
通过 gRPC 验证 brainstem 全流程。

用法:
    # 终端 1:
    ONNXRUNTIME_DLL_PATH=... dart run han_dog/bin/server.dart

    # 终端 2:
    python sim/scripts/test_fsm.py
"""
import math
import numpy as np
import mujoco
import mujoco_viewer
import grpc
import time, sys
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

CMS_NAMES = {0: "ZERO", 1: "GROUNDED", 2: "STANDING", 3: "WALKING", 4: "TRANSITIONING"}


def build_sim_state(data, elapsed_s):
    raw_q = data.sensor('orientation').data
    qw, qx, qy, qz = float(raw_q[0]), float(raw_q[1]), float(raw_q[2]), float(raw_q[3])
    gyro = data.sensor('angular-velocity').data
    joint_pos = [float(data.qpos[i]) for i in dof_ids]
    joint_vel = [float(data.qvel[i]) for i in dof_vel]
    seconds = int(elapsed_s)
    nanos = int((elapsed_s - seconds) * 1e9)
    return msg.SimState(
        gyroscope=msg.Vector3(x=float(gyro[0]), y=float(gyro[1]), z=float(gyro[2])),
        quaternion=msg.Quaternion(w=qw, x=qx, y=qy, z=qz),
        joint_position=msg.Matrix4(values=joint_pos),
        joint_velocity=msg.Matrix4(values=joint_vel),
        timestamp=msg.Duration(seconds=seconds, nanos=nanos),
    )


def dart_to_mj(d):
    mj = np.zeros(16)
    for leg in range(4):
        dd, m = leg*3, leg*4
        mj[m]=d[dd]; mj[m+1]=d[dd+1]; mj[m+2]=d[dd+2]; mj[m+3]=d[12+leg]
    return mj


def main():
    # ── 连接 ──────────────────────────────────────────────────
    print("Connecting to Dart server...")
    channel = grpc.insecure_channel("127.0.0.1:13145")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)
    print(f"Connected. CMS: {CMS_NAMES.get(stub.GetCmsState(msg.Empty()).kind, '?')}")

    # ── MuJoCo ────────────────────────────────────────────────
    model = mujoco.MjModel.from_xml_path("sim/robot/quadruped_v3.xml")
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    decimation = 4
    dt = 0.005

    data.qpos[:3] = [0, 0, 0.15]  # sitting pose
    data.qpos[3:7] = [1, 0, 0, 0]
    data.qpos[dof_ids] = np.zeros(16)  # sitting pose
    data.qvel[:] = 0
    mujoco.mj_step(model, data)

    viewer = mujoco_viewer.MujocoViewer(model, data)

    target_q = np.zeros(16, dtype=np.float64)
    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15,15,20]*4, dtype=np.float64)

    # ── 测试序列 ──────────────────────────────────────────────
    # (时间, 动作, 描述)
    sequence = [
        (0,   "wait",     "Grounded (idle)"),
        (2,   "standup",  "StandUp"),
        (6,   "walk_fwd", "Walk forward vx=0.3"),
        (12,  "walk_lat", "Walk lateral vy=0.3"),
        (16,  "walk_yaw", "Walk + yaw vx=0.2 vyaw=0.5"),
        (20,  "stop",     "StandUp (stop walking)"),
        (24,  "sitdown",  "SitDown"),
        (28,  "standup2", "StandUp again"),
        (32,  "walk_back","Walk backward vx=-0.3"),
        (36,  "stop2",    "StandUp (stop)"),
        (39,  "sitdown2", "SitDown (end)"),
        (43,  "done",     "Test complete"),
    ]

    seq_idx = 0
    count = 0
    last_cms = -1

    print(f"\n=== FSM Test Sequence ===")
    for t, action, desc in sequence:
        print(f"  [{t:2d}s] {desc}")
    print()

    try:
        while viewer.is_alive:
            now_s = count * dt

            # 执行序列
            if seq_idx < len(sequence) and now_s >= sequence[seq_idx][0]:
                _, action, desc = sequence[seq_idx]
                seq_idx += 1

                if action == "standup" or action == "standup2":
                    stub.StandUp(msg.Empty())
                    print(f"  [{now_s:.1f}s] >> StandUp sent")
                elif action == "sitdown" or action == "sitdown2":
                    stub.SitDown(msg.Empty())
                    print(f"  [{now_s:.1f}s] >> SitDown sent")
                elif action == "walk_fwd":
                    stub.Walk(msg.Vector3(x=0.3, y=0.0, z=0.0))
                    print(f"  [{now_s:.1f}s] >> Walk(0.3, 0, 0) sent")
                elif action == "walk_lat":
                    stub.Walk(msg.Vector3(x=0.0, y=0.3, z=0.0))
                    print(f"  [{now_s:.1f}s] >> Walk(0, 0.3, 0) sent")
                elif action == "walk_yaw":
                    stub.Walk(msg.Vector3(x=0.2, y=0.0, z=0.5))
                    print(f"  [{now_s:.1f}s] >> Walk(0.2, 0, 0.5) sent")
                elif action == "walk_back":
                    stub.Walk(msg.Vector3(x=-0.3, y=0.0, z=0.0))
                    print(f"  [{now_s:.1f}s] >> Walk(-0.3, 0, 0) sent")
                elif action == "stop" or action == "stop2":
                    stub.StandUp(msg.Empty())
                    print(f"  [{now_s:.1f}s] >> StandUp (stop) sent")
                elif action == "done":
                    print(f"\n  [{now_s:.1f}s] === TEST COMPLETE ===")
                    break

            if count % decimation == 0:
                # Step + Tick
                sim_state = build_sim_state(data, now_s)
                stub.Step(sim_state)

                cms = stub.GetCmsState(msg.Empty())
                if cms.kind != last_cms:
                    print(f"  [{now_s:.1f}s] CMS: {CMS_NAMES.get(last_cms, '?')} -> {CMS_NAMES.get(cms.kind, '?')}")
                    last_cms = cms.kind

                history = stub.Tick(msg.Empty())
                target_q = np.array(history.next_action.values, dtype=np.float64)

                if len(history.kp.values) == 16:
                    kp = np.array(history.kp.values[:12], dtype=np.float64)
                if len(history.kd.values) == 16:
                    kd = np.array(history.kd.values[:12], dtype=np.float64)

            # PD 每步算
            q = data.qpos[dof_ids].astype(np.float64)
            dq = data.qvel[dof_vel].astype(np.float64)
            tau = np.zeros(16)
            tau[:12] = kp * (target_q[:12] - q[:12]) - kd * dq[:12]
            tau[12:] = 1.0 * (target_q[12:] - dq[12:])
            data.ctrl[:] = np.clip(tau, -120, 120)

            mujoco.mj_step(model, data)
            count += 1

            if count % decimation == 0:
                viewer.render()

            # 每 2 秒打印位置
            if count % int(2.0 / dt) == 0:
                x, y, z = data.qpos[0], data.qpos[1], data.qpos[2]
                print(f"  [{now_s:.1f}s] pos=({x:.2f}, {y:.2f}, {z:.3f}) {CMS_NAMES.get(last_cms, '?')}")

    except KeyboardInterrupt:
        print("\nStopped")
    finally:
        viewer.close()
        channel.close()


if __name__ == "__main__":
    main()
