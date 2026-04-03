"""最简示例：3 行代码让机器人走路。"""

from brainstem_sdk import ThunderClient

dog = ThunderClient("192.168.66.190")

# 使能电机
dog.enable()

# 站起来
dog.stand_up()
input("机器人已站立。按 Enter 开始走路...")

# 向前走 (vx=0.3 表示 30% 速度前进)
dog.walk(vx=0.3)
input("正在走路。按 Enter 停止...")

# 停止走路 → 坐下 → 禁用电机
dog.walk(vx=0.0)
dog.sit_down()
dog.disable()
print("完成。")
