"""
Xbox 手柄远程控制真机。纯 gRPC 客户端，不需要 MuJoCo。

本地电脑 Xbox 手柄 → gRPC → sunrise Dart server (han_dog.dart) → PCAN 电机

用法:
    # sunrise 上跑:
    cd ~/data/brainstem && ~/data/dart-sdk/bin/dart run han_dog/bin/han_dog.dart

    # 本地电脑跑:
    python sim/scripts/xbox_remote.py --host 192.168.66.190
"""
import grpc
import pygame
import sys, time, argparse
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROTO_PY_ROOT = SCRIPT_DIR.parent.parent / "han_dog_message" / "python"
if str(PROTO_PY_ROOT) not in sys.path:
    sys.path.insert(0, str(PROTO_PY_ROOT))
import han_dog_message as msg

DEADZONE = 0.08
CMS_NAMES = {0: "ZERO", 1: "GROUNDED", 2: "STANDING", 3: "WALKING", 4: "TRANSITIONING"}


def dz(val):
    return 0.0 if abs(val) < DEADZONE else val


def safe_call(fn, *a, **kw):
    try:
        return fn(*a, **kw)
    except grpc.RpcError:
        return None


def main():
    parser = argparse.ArgumentParser(description="Xbox remote control for Thunder")
    parser.add_argument("--host", default="192.168.66.190")
    parser.add_argument("--port", type=int, default=13145)
    args = parser.parse_args()

    # ── pygame + joystick ─────────────────────────────────────
    pygame.init()
    pygame.joystick.init()
    if pygame.joystick.get_count() == 0:
        print("No joystick found! Connect Xbox controller and retry.")
        return
    joy = pygame.joystick.Joystick(0)
    joy.init()
    print(f"Joystick: {joy.get_name()}")

    # ── gRPC ──────────────────────────────────────────────────
    target = f"{args.host}:{args.port}"
    print(f"Connecting to {target}...")
    channel = grpc.insecure_channel(target)
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
    except grpc.FutureTimeoutError:
        print(f"Connection timeout! Is han_dog.dart running on {args.host}?")
        return
    stub = msg.CmsStub(channel)
    print("Connected!")

    enabled = False
    walking = False
    last_btn = {}
    last_cms = -1

    print()
    print("=" * 50)
    print("  Thunder Remote Control")
    print("=" * 50)
    print()
    print("  Y          : Enable/Disable (电机使能)")
    print("  A          : StandUp")
    print("  X          : SitDown")
    print("  Left stick : Walk")
    print("  Right stick: Yaw")
    print("  LT/RT      : Slow/Fast")
    print("  Back/Select: SetZero (标零)")
    print("  B          : Quit")
    print()

    def btn_pressed(idx):
        cur = joy.get_button(idx) if idx < joy.get_numbuttons() else 0
        prev = last_btn.get(idx, 0)
        last_btn[idx] = cur
        return cur and not prev

    try:
        while True:
            time.sleep(0.02)  # 50Hz
            pygame.event.pump()

            # ── 读摇杆 ───────────────────────────────────────
            lx = dz(joy.get_axis(0))
            ly = dz(-joy.get_axis(1))
            rx = dz(joy.get_axis(2) if joy.get_numaxes() > 2 else 0)

            scale = 1.0
            if joy.get_numaxes() >= 6:
                lt = (joy.get_axis(4) + 1) / 2
                rt = (joy.get_axis(5) + 1) / 2
                if lt > 0.3:
                    scale = 0.5
                elif rt > 0.3:
                    scale = 1.5

            vx = ly * scale
            vy = lx * scale
            vyaw = -rx * scale

            # ── 按钮 ─────────────────────────────────────────

            # Y = Enable/Disable
            if btn_pressed(3):
                if not enabled:
                    safe_call(stub.Enable, msg.Empty())
                    enabled = True
                    print("  >> Enable (电机使能)")
                else:
                    safe_call(stub.Disable, msg.Empty())
                    enabled = False
                    walking = False
                    print("  >> Disable (电机关闭)")

            # A = StandUp
            if btn_pressed(0):
                safe_call(stub.StandUp, msg.Empty())
                walking = False
                print("  >> StandUp")

            # X = SitDown
            if btn_pressed(2):
                safe_call(stub.SitDown, msg.Empty())
                walking = False
                print("  >> SitDown")

            # Back/Select = SetZero
            if btn_pressed(6):
                result = safe_call(stub.SetZero, msg.Empty())
                if result is not None:
                    print("  >> SetZero (标零完成)")
                else:
                    print("  >> SetZero 失败 (需在 Grounded 状态)")

            # B = Quit
            if btn_pressed(1):
                print("  >> Quit")
                break

            # ── 摇杆 → Walk ──────────────────────────────────
            stick_active = abs(vx) > 0.01 or abs(vy) > 0.01 or abs(vyaw) > 0.01
            if stick_active:
                safe_call(stub.Walk, msg.Vector3(x=vx, y=vy, z=vyaw))
                if not walking:
                    print(f"  >> Walk started")
                    walking = True
            elif walking:
                safe_call(stub.Walk, msg.Vector3(x=0, y=0, z=0))

    except KeyboardInterrupt:
        print("\nStopped")
    finally:
        # 安全：退出前 SitDown + Disable
        print("  Shutting down: SitDown + Disable...")
        safe_call(stub.SitDown, msg.Empty())
        time.sleep(0.5)
        safe_call(stub.Disable, msg.Empty())
        channel.close()
        pygame.quit()


if __name__ == "__main__":
    main()
