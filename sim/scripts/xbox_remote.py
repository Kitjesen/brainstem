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

from xbox_config import XboxController, load_xbox_config


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

    # ── Xbox 配置 ─────────────────────────────────────────────
    xbox = XboxController(joy)

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

    try:
        while True:
            time.sleep(0.02)  # 50Hz
            pygame.event.pump()

            # ── 按钮 ─────────────────────────────────────────

            # Y = Enable/Disable
            if xbox.btn_pressed("enable"):
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
            if xbox.btn_pressed("standup"):
                safe_call(stub.StandUp, msg.Empty())
                walking = False
                print("  >> StandUp")

            # X = SitDown
            if xbox.btn_pressed("sitdown"):
                safe_call(stub.SitDown, msg.Empty())
                walking = False
                print("  >> SitDown")

            # Back/Select = SetZero
            if xbox.btn_pressed("set_zero"):
                result = safe_call(stub.SetZero, msg.Empty())
                if result is not None:
                    print("  >> SetZero (标零完成)")
                else:
                    print("  >> SetZero 失败 (需在 Grounded 状态)")

            # B = Quit
            if xbox.btn_pressed("quit"):
                print("  >> Quit")
                break

            # ── 摇杆 → Walk ──────────────────────────────────
            if xbox.stick_active:
                safe_call(stub.Walk, msg.Vector3(x=xbox.vx, y=xbox.vy, z=xbox.vyaw))
                if not walking:
                    print("  >> Walk started")
                    walking = True
            elif walking:
                safe_call(stub.Walk, msg.Vector3(x=0, y=0, z=0))

    except KeyboardInterrupt:
        print("\nStopped")
    finally:
        print("  Shutting down: SitDown + Disable...")
        safe_call(stub.SitDown, msg.Empty())
        time.sleep(0.5)
        safe_call(stub.Disable, msg.Empty())
        channel.close()
        pygame.quit()


if __name__ == "__main__":
    main()
