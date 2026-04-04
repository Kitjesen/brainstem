"""动作演示：让机器狗鞠躬、点头、跳舞。"""

import time
from brainstem_sdk import ThunderClient

dog = ThunderClient("192.168.66.190")
try:
    # 查看所有可用动作
    gestures = dog.list_gestures()
    print("可用动作:")
    for g in gestures:
        print(f"  {g['name']:10s} — {g['description']} ({g['duration_ms']}ms)")

    # 使能 + 站起
    dog.enable()
    dog.stand_up()
    input("机器狗已站立。按 Enter 开始动作演示...")

    # 逐个播放
    for g in gestures:
        name = g["name"]
        print(f"\n播放: {name} ({g['description']})...")
        dog.play_gesture(name)
        time.sleep(1)  # 动作间隔

    print("\n演示完成。")
finally:
    try:
        dog.sit_down()
    except Exception:
        pass
    try:
        dog.disable()
    except Exception:
        pass
    dog.close()
