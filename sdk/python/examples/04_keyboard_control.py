"""键盘控制：WASD 操控机器人行走。

W/S = 前进/后退
A/D = 左移/右移
Q/E = 左转/右转
Space = 停止
U = 站起
J = 坐下
Enter = 退出
"""

import sys
import termios
import tty
from brainstem_sdk import ThunderClient


def getch():
    """读取单个按键（Linux/macOS）。"""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def main():
    dog = ThunderClient("192.168.66.190")
    dog.enable()

    speed = 0.4
    print("键盘控制已启动 (按 Enter 退出)")
    print("W/S=前后  A/D=左右  Q/E=旋转  Space=停  U=站起  J=坐下")

    try:
        while True:
            key = getch().lower()
            if key == "\r":
                break
            elif key == "w":
                dog.walk(vx=speed)
            elif key == "s":
                dog.walk(vx=-speed)
            elif key == "a":
                dog.walk(vy=speed)
            elif key == "d":
                dog.walk(vy=-speed)
            elif key == "q":
                dog.walk(vyaw=speed)
            elif key == "e":
                dog.walk(vyaw=-speed)
            elif key == " ":
                dog.walk()
            elif key == "u":
                dog.stand_up()
            elif key == "j":
                dog.sit_down()
    except KeyboardInterrupt:
        pass
    finally:
        dog.walk()
        dog.sit_down()
        dog.disable()
        dog.close()
        print("\n已退出。")


if __name__ == "__main__":
    main()
