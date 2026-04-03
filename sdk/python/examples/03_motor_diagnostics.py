"""电机诊断：读取电压、温度、状态。"""

from brainstem_sdk import ThunderClient

dog = ThunderClient("192.168.66.190")

# 读取电压
voltages = dog.get_voltage()
print("电机电压 (V):")
for i, v in enumerate(voltages):
    print(f"  Joint {i:2d}: {v:.1f}V")

print()

# 读取电机状态
motors = dog.get_motor_status()
print("电机状态:")
for m in motors:
    status = "OK" if m.online and not m.errors else "FAULT"
    print(
        f"  Joint {m.id:2d}: {status:5s}  "
        f"temp={m.temperature:.0f}C  "
        f"pos={m.position:+.3f}rad  "
        f"errors={m.errors or 'none'}"
    )

# 查看当前状态
state = dog.get_state()
print(f"\n机器人状态: {state}")

dog.close()
