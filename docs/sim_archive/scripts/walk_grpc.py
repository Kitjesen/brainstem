"""
gRPC 闭环验证：物理循环和 walk_ref.py 完全一致，推理走 Dart server。
用于验证 brainstem 内部逻辑是否正确。

用法:
    # 终端 1:
    ONNXRUNTIME_DLL_PATH=... dart run han_dog/bin/server.dart

    # 终端 2:
    python sim/walk_grpc.py --vx 0.3 --duration 10 --render
"""
import math
import numpy as np
import mujoco
import grpc
import argparse, os, sys
from pathlib import Path
from scipy.spatial.transform import Rotation as R
from collections import deque

SCRIPT_DIR = Path(__file__).resolve().parent
PROTO_PY_ROOT = SCRIPT_DIR.parent.parent / "han_dog_message" / "python"
if str(PROTO_PY_ROOT) not in sys.path:
    sys.path.insert(0, str(PROTO_PY_ROOT))
import han_dog_message as msg

# ── 关节索引 ─────────────────────────────────────────────────
dof_ids = [7,8,9, 11,12,13, 15,16,17, 19,20,21, 10,14,18,22]
dof_vel = [6,7,8, 10,11,12, 14,15,16, 18,19,20, 9,13,17,21]

default_angle = np.array([
    -0.1, -0.8, 1.8,
     0.1,  0.8, -1.8,
     0.1,  0.8, -1.8,
    -0.1, -0.8, 1.8,
     0.0,  0.0,  0.0, 0.0,
], dtype=np.double)

CMS_GROUNDED = 1
CMS_STANDING = 2
CMS_WALKING = 3


def build_sim_state(data, elapsed_s):
    """传感器数据 → gRPC SimState（传给 Dart server）。"""
    # 四元数: sensor 输出 body→world [w,x,y,z]
    # Dart 的 q.rotate([0,0,-1]) 需要 world→body → 取共轭
    raw_q = data.sensor('orientation').data
    qw, qx, qy, qz = float(raw_q[0]), float(raw_q[1]), float(raw_q[2]), float(raw_q[3])

    # 角速度: sensor body-frame
    gyro = data.sensor('angular-velocity').data

    # 关节: MuJoCo 4x4 → Dart 12+4
    joint_pos = data.qpos[dof_ids].tolist()
    joint_vel = data.qvel[dof_vel].tolist()

    seconds = int(elapsed_s)
    nanos = int((elapsed_s - seconds) * 1e9)
    return msg.SimState(
        gyroscope=msg.Vector3(x=float(gyro[0]), y=float(gyro[1]), z=float(gyro[2])),
        quaternion=msg.Quaternion(w=qw, x=qx, y=qy, z=qz),
        joint_position=msg.Matrix4(values=[float(v) for v in joint_pos]),
        joint_velocity=msg.Matrix4(values=[float(v) for v in joint_vel]),
        timestamp=msg.Duration(seconds=seconds, nanos=nanos),
    )


def run(args):
    # ── 1. 连接 Dart server ───────────────────────────────────
    print(f"Connecting to {args.host}:{args.port}...")
    channel = grpc.insecure_channel(f"{args.host}:{args.port}")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)
    state = stub.GetCmsState(msg.Empty())
    print(f"CMS state: {state.kind} (expect {CMS_GROUNDED}=Grounded)")

    # ── 2. MuJoCo ────────────────────────────────────────────
    model = mujoco.MjModel.from_xml_path(args.xml)
    model.opt.timestep = 0.005  # 和 walk_ref 一致
    data = mujoco.MjData(model)
    decimation = 4
    dt = 0.005

    data.qpos[:3] = [0, 0, 0.15]  # sitting pose
    data.qpos[3:7] = [1, 0, 0, 0]
    data.qpos[dof_ids] = np.zeros(16)  # sitting pose
    data.qvel[:] = 0
    mujoco.mj_step(model, data)

    # PD 增益 (训练值)
    kp = np.array([70,100,120, 70,100,120, 70,100,120, 70,100,120], dtype=np.float64)
    kd = np.array([15, 15, 20, 15, 15, 20, 15, 15, 20, 15, 15, 20], dtype=np.float64)

    target_q = np.zeros(16, dtype=np.float64)
    standup_sent = False
    walk_sent = False

    renderer = None
    frames = []
    if args.render:
        renderer = mujoco.Renderer(model, width=640, height=480)
        cam = mujoco.MjvCamera()
        cam.type = mujoco.mjtCamera.mjCAMERA_TRACKING
        cam.trackbodyid = model.body('trunk').id
        cam.distance = 2.5
        cam.azimuth = 180
        cam.elevation = -20

    sim_steps = int(args.duration / dt)
    count = 0
    print(f"Running {sim_steps} steps ({args.duration}s), decimation={decimation}")

    for i in range(sim_steps):
        now_s = count * dt

        if count % decimation == 0:
            # Step: 注入传感器
            sim_state = build_sim_state(data, now_s)
            stub.Step(sim_state)

            # FSM 控制
            cms = stub.GetCmsState(msg.Empty())

            if not standup_sent and cms.kind == CMS_GROUNDED:
                stub.StandUp(msg.Empty())
                standup_sent = True

            if standup_sent and not walk_sent and cms.kind == CMS_STANDING:
                stub.Walk(msg.Vector3(x=args.vx, y=args.vy, z=args.vyaw))
                walk_sent = True

            # Tick: Dart 推理
            history = stub.Tick(msg.Empty())
            target_q = np.array(history.next_action.values, dtype=np.float64)

            # 动态 kp/kd (从 History 读)
            if len(history.kp.values) == 16:
                kp = np.array(history.kp.values[:12], dtype=np.float64)
            if len(history.kd.values) == 16:
                kd = np.array(history.kd.values[:12], dtype=np.float64)

        # PD 每步都算 (200Hz)
        q = data.qpos[dof_ids].astype(np.float64)
        dq = data.qvel[dof_vel].astype(np.float64)
        tau = np.zeros(16)
        tau[:12] = kp * (target_q[:12] - q[:12]) - kd * dq[:12]
        tau[12:] = 1.0 * (target_q[12:] - dq[12:])
        tau = np.clip(tau, -120, 120)
        data.ctrl[:] = tau

        mujoco.mj_step(model, data)
        count += 1

        if renderer and count % decimation == 0:
            renderer.update_scene(data, camera=cam)
            frames.append(renderer.render().copy())

        if count % int(1.0 / dt) == 0:
            x, y, z = data.qpos[0], data.qpos[1], data.qpos[2]
            mode = "WALK" if walk_sent else ("STANDUP" if standup_sent else "GROUND")
            print(f"  [{now_s:.1f}s] pos=({x:.3f}, {y:.3f}, {z:.3f}) {mode}")

    x, y = data.qpos[0], data.qpos[1]
    print(f"\nFinal: x={x:.3f} y={y:.3f} disp={math.sqrt(x**2+y**2):.3f}")

    if renderer and frames:
        out_dir = SCRIPT_DIR.parent / "output"
        os.makedirs(out_dir, exist_ok=True)
        video_path = str(out_dir / "walk_grpc.mp4")
        try:
            import imageio
            imageio.mimsave(video_path, frames, fps=50)
            print(f"Video: {video_path} ({len(frames)} frames)")
        except ImportError:
            print(f"imageio not installed ({len(frames)} frames)")
        renderer.close()

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
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    run(args)
