"""
Xbox 手柄 + brainstem gRPC 全链路验证。

手柄 → gRPC → Dart server (FSM + ONNX 推理) → gRPC → MuJoCo 物理

控制映射 (和真机遥控器对齐):
    左摇杆 Y     : 前后移动 (vx)
    左摇杆 X     : 左右侧移 (vy)
    右摇杆 X     : 旋转 yaw
    LT / RT      : 慢速 0.5x / 快速 1.5x
    A (按钮0)    : StandUp
    X (按钮2)    : SitDown
    Y (按钮3)    : Walk(0,0,0) 原地
    B (按钮1)    : 退出

FSM 流程: Grounded → [A]StandUp → Standing → [摇杆]Walk → [A]StandUp → [X]SitDown → Grounded

用法:
    # 终端 1:
    ONNXRUNTIME_DLL_PATH=... dart run han_dog/bin/server.dart

    # 终端 2:
    python sim/scripts/xbox_brainstem.py
"""
import math
import numpy as np
import mujoco
import mujoco_viewer
import grpc
import pygame
import sys, time
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

CMS_NAMES = {0: "ZERO", 1: "GROUNDED", 2: "STANDING", 3: "WALKING", 4: "TRANSITIONING"}
DEADZONE = 0.08


def build_sim_state(data, elapsed_s):
    raw_q = data.sensor('orientation').data
    qw = float(raw_q[0])
    qx, qy, qz = float(raw_q[1]), float(raw_q[2]), float(raw_q[3])
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


def dz(val):
    return 0.0 if abs(val) < DEADZONE else val


def main():
    # ── pygame + joystick ─────────────────────────────────────
    pygame.init()
    pygame.joystick.init()
    if pygame.joystick.get_count() == 0:
        print("No joystick found!")
        return
    joy = pygame.joystick.Joystick(0)
    joy.init()
    print(f"Joystick: {joy.get_name()}")

    # ── gRPC ──────────────────────────────────────────────────
    print("Connecting to brainstem...")
    channel = grpc.insecure_channel("127.0.0.1:13145")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)
    cms = stub.GetCmsState(msg.Empty())
    print(f"Connected. CMS: {CMS_NAMES.get(cms.kind, '?')}")

    # ── MuJoCo ────────────────────────────────────────────────
    model = mujoco.MjModel.from_xml_path("sim/robot/quadruped_v3.xml")
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    decimation = 4
    dt = 0.005

    # 初始 sittingPose（全零，趴地）
    sitting_pose = np.zeros(16, dtype=np.float64)
    data.qpos[:3] = [0, 0, 0.25]  # 零姿态时的大致高度
    data.qpos[3:7] = [1, 0, 0, 0]
    data.qpos[dof_ids] = sitting_pose
    data.qvel[:] = 0
    mujoco.mj_step(model, data)

    viewer = mujoco_viewer.MujocoViewer(model, data)

    target_q = sitting_pose.copy()
    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15,15,20]*4, dtype=np.float64)

    count = 0
    last_cms = -1
    last_btn = {}
    walking = False
    last_walk_time = 0.0

    print()
    print("Controls:")
    print("  A        : StandUp")
    print("  X        : SitDown")
    print("  Left stick : Walk (auto sends Walk command)")
    print("  Right stick X : Yaw")
    print("  LT/RT    : Slow/Fast")
    print("  B        : Quit")
    print()

    try:
        while viewer.is_alive:
            t_start = time.perf_counter()
            now_s = count * dt

            # ── 读手柄 ────────────────────────────────────────
            pygame.event.pump()

            lx = dz(joy.get_axis(0))     # left/right
            ly = dz(-joy.get_axis(1))    # forward (Y inverted)
            rx = dz(joy.get_axis(2) if joy.get_numaxes() > 2 else 0)

            # Speed scale (LT/RT)
            scale = 1.0
            if joy.get_numaxes() >= 6:
                lt = (joy.get_axis(4) + 1) / 2
                rt = (joy.get_axis(5) + 1) / 2
                if lt > 0.3:
                    scale = 0.5
                elif rt > 0.3:
                    scale = 1.5

            # 直接透传摇杆值，不限速（策略自己有 clamp）
            vx = ly * scale      # 满量程 ±1.0 (±1.5 with RT)
            vy = lx * scale      # 满量程 ±1.0
            vyaw = -rx * scale   # 满量程 ±1.0

            # Button events (edge detect)
            def btn_pressed(idx):
                cur = joy.get_button(idx) if idx < joy.get_numbuttons() else 0
                prev = last_btn.get(idx, 0)
                last_btn[idx] = cur
                return cur and not prev

            # 安全封装：所有 gRPC 调用都容错
            def safe_call(fn, *a, **kw):
                try:
                    return fn(*a, **kw)
                except grpc.RpcError:
                    return None

            # A = StandUp
            if btn_pressed(0):
                safe_call(stub.StandUp, msg.Empty())
                walking = False
                print(f"  [{now_s:.1f}s] >> StandUp")

            # X = SitDown
            if btn_pressed(2):
                safe_call(stub.SitDown, msg.Empty())
                walking = False
                print(f"  [{now_s:.1f}s] >> SitDown")

            # B = Quit
            if btn_pressed(1):
                print("  >> Quit")
                break

            # 摇杆 → 实时发 Walk（含零速度，让机器狗跟随）
            stick_active = abs(vx) > 0.01 or abs(vy) > 0.01 or abs(vyaw) > 0.01
            if stick_active:
                safe_call(stub.Walk, msg.Vector3(x=vx, y=vy, z=vyaw))
                if not walking:
                    print(f"  [{now_s:.1f}s] >> Walk started")
                    walking = True
            elif walking:
                # 松摇杆 → 发 Walk(0,0,0) 让机器狗停住（保持 Walking 状态）
                safe_call(stub.Walk, msg.Vector3(x=0, y=0, z=0))

            # ── 物理循环 ──────────────────────────────────────
            for _ in range(decimation):
                if count % decimation == 0:
                    # Step + Tick (核心：每推理帧 2 次 gRPC)
                    sim_state = build_sim_state(data, now_s)
                    stub.Step(sim_state)

                    history = stub.Tick(msg.Empty())
                    target_q = np.array(history.next_action.values, dtype=np.float64)

                    if len(history.kp.values) == 16:
                        kp = np.array(history.kp.values[:12], dtype=np.float64)
                    if len(history.kd.values) == 16:
                        kd = np.array(history.kd.values[:12], dtype=np.float64)

                    # CMS 状态低频查询（每 10 帧一次）
                    if count % (decimation * 10) == 0:
                        cms = safe_call(stub.GetCmsState, msg.Empty())
                        if cms and cms.kind != last_cms:
                            print(f"  [{now_s:.1f}s] CMS: {CMS_NAMES.get(last_cms, '?')} -> {CMS_NAMES.get(cms.kind, '?')}")
                            last_cms = cms.kind

                # PD
                q = data.qpos[dof_ids].astype(np.float64)
                dq_val = data.qvel[dof_vel].astype(np.float64)
                tau = np.zeros(16)
                tau[:12] = kp * (target_q[:12] - q[:12]) - kd * dq_val[:12]
                tau[12:] = 1.0 * (target_q[12:] - dq_val[12:])
                data.ctrl[:] = np.clip(tau, -120, 120)

                mujoco.mj_step(model, data)
                count += 1

            viewer.render()

            # 每 2 秒打印
            if count % int(2.0 / dt) == 0:
                x, y, z = data.qpos[0], data.qpos[1], data.qpos[2]
                cmd_str = f"cmd=({vx:.2f},{vy:.2f},{vyaw:.2f})" if walking else ""
                print(f"  [{now_s:.1f}s] pos=({x:.2f},{y:.2f},{z:.3f}) {CMS_NAMES.get(last_cms,'?')} {cmd_str}")

            # 实时控制
            elapsed = time.perf_counter() - t_start
            sleep_time = (decimation * dt) - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\nStopped")
    finally:
        viewer.close()
        channel.close()
        pygame.quit()


if __name__ == "__main__":
    main()
