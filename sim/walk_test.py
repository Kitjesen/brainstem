"""
brainstem MuJoCo 行走闭环测试。

启动 Dart server → MuJoCo 物理 → gRPC 闭环：
  StandUp → Walk(vx, 0, 0) → 验证位移 → SitDown

用法:
    # 终端 1: 启动 Dart server
    dart run han_dog/bin/server.dart

    # 终端 2: 跑仿真
    python sim/walk_test.py
    python sim/walk_test.py --vx 0.5 --duration 5 --render

依赖: pip install mujoco grpc grpcio numpy
"""

from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

import grpc
import mujoco
import numpy as np

# ── proto 路径 ────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
BRAINSTEM_ROOT = SCRIPT_DIR.parent
PROTO_PY_ROOT = BRAINSTEM_ROOT / "han_dog_message" / "python"
if str(PROTO_PY_ROOT) not in sys.path:
    sys.path.insert(0, str(PROTO_PY_ROOT))

import han_dog_message as msg  # noqa: E402

# ── 常量 ──────────────────────────────────────────────────────
MODEL_XML = SCRIPT_DIR / "quadruped.xml"
CONTROL_HZ = 50.0
MUJOCO_DT = 0.002
SUBSTEPS = int(round((1.0 / CONTROL_HZ) / MUJOCO_DT))

STANDING_POSE_DART = [
    -0.1, -0.8, 1.8,
     0.1,  0.8, -1.8,
     0.1,  0.8, -1.8,
    -0.1, -0.8, 1.8,
     0.0,  0.0,  0.0, 0.0,
]

CMS_STATE_GROUNDED = 1
CMS_STATE_STANDING = 2
CMS_STATE_WALKING = 3


# ── Dart ↔ MuJoCo 关节转换 ────────────────────────────────────

def dart_to_mujoco(dart16: list[float]) -> list[float]:
    mj = [0.0] * 16
    for leg in range(4):
        d, m = leg * 3, leg * 4
        mj[m + 0] = -float(dart16[d + 0])
        mj[m + 1] = -float(dart16[d + 1])
        mj[m + 2] = -float(dart16[d + 2])
        mj[m + 3] = -float(dart16[12 + leg])
    return mj


def mujoco_to_dart(mj16) -> list[float]:
    mj = list(mj16)
    dart16 = [0.0] * 16
    for leg in range(4):
        d, m = leg * 3, leg * 4
        dart16[d + 0] = -float(mj[m + 0])
        dart16[d + 1] = -float(mj[m + 1])
        dart16[d + 2] = -float(mj[m + 2])
        dart16[12 + leg] = -float(mj[m + 3])
    return dart16


def dart_gains_to_mujoco(dart16: list[float]) -> list[float]:
    mj = [0.0] * 16
    for leg in range(4):
        d, m = leg * 3, leg * 4
        mj[m + 0] = float(dart16[d + 0])
        mj[m + 1] = float(dart16[d + 1])
        mj[m + 2] = float(dart16[d + 2])
        mj[m + 3] = float(dart16[12 + leg])
    return mj


def invert_quat_wxyz(q):
    w, x, y, z = q
    return (w, -x, -y, -z)


# ── SimState / History 转换 ───────────────────────────────────

def build_sim_state(data: mujoco.MjData, elapsed_s: float) -> msg.SimState:
    qpos, qvel = data.qpos, data.qvel
    world_to_body = invert_quat_wxyz(
        (float(qpos[3]), float(qpos[4]), float(qpos[5]), float(qpos[6]))
    )
    seconds = int(elapsed_s)
    nanos = int((elapsed_s - seconds) * 1e9)
    return msg.SimState(
        gyroscope=msg.Vector3(x=float(qvel[3]), y=float(qvel[4]), z=float(qvel[5])),
        quaternion=msg.Quaternion(w=world_to_body[0], x=world_to_body[1],
                                  y=world_to_body[2], z=world_to_body[3]),
        joint_position=msg.Matrix4(values=mujoco_to_dart(qpos[7:23])),
        joint_velocity=msg.Matrix4(values=mujoco_to_dart(qvel[6:22])),
        timestamp=msg.Duration(seconds=seconds, nanos=nanos),
    )


def apply_history(history: msg.History, model: mujoco.MjModel, data: mujoco.MjData):
    data.ctrl[:] = dart_to_mujoco(list(history.next_action.values))
    if len(history.kp.values) == 16 and len(history.kd.values) == 16:
        kp = dart_gains_to_mujoco(list(history.kp.values))
        kd = dart_gains_to_mujoco(list(history.kd.values))
        for i in range(16):
            model.actuator_gainprm[i, 0] = kp[i]
            model.actuator_biasprm[i, 1] = -kp[i]
            model.actuator_biasprm[i, 2] = -kd[i]


# ── 主流程 ────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="brainstem MuJoCo walk test")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="Dart server host")
    parser.add_argument("--port", type=int, default=13145)
    parser.add_argument("--vx", type=float, default=0.5, help="forward speed command")
    parser.add_argument("--vy", type=float, default=0.0, help="lateral speed command")
    parser.add_argument("--vyaw", type=float, default=0.0, help="yaw rate command")
    parser.add_argument("--duration", type=float, default=5.0, help="walk duration (s)")
    parser.add_argument("--render", action="store_true", help="show MuJoCo viewer")
    args = parser.parse_args()

    # ── 1. 连接 Dart server ────────────────────────────────────
    print(f"Connecting to Dart server at {args.host}:{args.port}...")
    channel = grpc.insecure_channel(f"{args.host}:{args.port}")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)

    state = stub.GetCmsState(msg.Empty())
    print(f"CMS state: {state.kind} (expected: {CMS_STATE_GROUNDED}=Grounded)")

    # ── 2. 加载 MuJoCo ────────────────────────────────────────
    print(f"Loading MuJoCo model: {MODEL_XML}")
    model = mujoco.MjModel.from_xml_path(str(MODEL_XML))
    data = mujoco.MjData(model)

    standing_mj = dart_to_mujoco(STANDING_POSE_DART)
    data.qpos[0:3] = [0, 0, 0.45]
    data.qpos[3:7] = [1, 0, 0, 0]  # identity quaternion
    data.qpos[7:23] = standing_mj
    data.qvel[:] = 0
    data.ctrl[:] = standing_mj
    mujoco.mj_forward(model, data)
    for _ in range(50):
        mujoco.mj_step(model, data)

    start_x = float(data.qpos[0])
    print(f"Initial position: x={start_x:.3f}")

    # ── 3. 仿真循环 ───────────────────────────────────────────
    viewer = None
    if args.render:
        viewer = mujoco.viewer.launch_passive(model, data)

    standup_sent = False
    walk_sent = False
    walk_start_step = None
    total_steps = int((args.duration + 5) * CONTROL_HZ)  # extra 5s for standup

    print(f"\nRunning {total_steps} steps ({total_steps / CONTROL_HZ:.1f}s)...")
    print(f"  Walk command: vx={args.vx}, vy={args.vy}, vyaw={args.vyaw}")

    for step in range(total_steps):
        now_s = step / CONTROL_HZ

        # Step: 注入传感器数据
        sim_state = build_sim_state(data, now_s)
        stub.Step(sim_state)

        # 状态机控制
        cms = stub.GetCmsState(msg.Empty())

        if not standup_sent and cms.kind == CMS_STATE_GROUNDED:
            stub.StandUp(msg.Empty())
            standup_sent = True
            print(f"  [{now_s:.1f}s] StandUp sent")

        if standup_sent and not walk_sent and cms.kind == CMS_STATE_STANDING:
            stub.Walk(msg.Vector3(x=args.vx, y=args.vy, z=args.vyaw))
            walk_sent = True
            walk_start_step = step
            print(f"  [{now_s:.1f}s] Walk({args.vx}, {args.vy}, {args.vyaw}) sent")

        if walk_sent and cms.kind in (CMS_STATE_STANDING, CMS_STATE_WALKING):
            stub.Walk(msg.Vector3(x=args.vx, y=args.vy, z=args.vyaw))

        # 检查行走时长
        if walk_start_step is not None and (step - walk_start_step) / CONTROL_HZ >= args.duration:
            break

        # Tick: 推理 → 获取 action
        history = stub.Tick(msg.Empty())
        apply_history(history, model, data)

        # 物理步进
        for _ in range(SUBSTEPS):
            mujoco.mj_step(model, data)

        if viewer is not None:
            viewer.sync()

        # 每秒打印一次位置
        if step % int(CONTROL_HZ) == 0:
            x, y = float(data.qpos[0]), float(data.qpos[1])
            z = float(data.qpos[2])
            print(f"  [{now_s:.1f}s] pos=({x:.3f}, {y:.3f}, {z:.3f}) cms={cms.kind}")

    # ── 4. 结果 ───────────────────────────────────────────────
    final_x = float(data.qpos[0])
    final_y = float(data.qpos[1])
    displacement = math.sqrt((final_x - start_x) ** 2 + final_y ** 2)

    print(f"\n{'=' * 50}")
    print(f"  Start:  x={start_x:.3f}")
    print(f"  Final:  x={final_x:.3f}, y={final_y:.3f}")
    print(f"  Displacement: {displacement:.3f} m")
    print(f"  Command: vx={args.vx}")

    if args.vx > 0 and final_x > start_x + 0.1:
        print(f"  Result: PASS (moved forward)")
    elif args.vx < 0 and final_x < start_x - 0.1:
        print(f"  Result: PASS (moved backward)")
    elif args.vx == 0 and displacement < 0.3:
        print(f"  Result: PASS (stayed in place)")
    else:
        print(f"  Result: CHECK (unexpected displacement)")
    print(f"{'=' * 50}")

    channel.close()
    if viewer is not None:
        viewer.close()


if __name__ == "__main__":
    main()
