"""电机操作全流程：诊断、清错、标零、增益监控。"""

import time
from brainstem_sdk import ThunderClient

JOINT_NAMES = [
    "FR Hip", "FR Thigh", "FR Calf", "FR Foot",
    "FL Hip", "FL Thigh", "FL Calf", "FL Foot",
    "RR Hip", "RR Thigh", "RR Calf", "RR Foot",
    "RL Hip", "RL Thigh", "RL Calf", "RL Foot",
]

dog = ThunderClient("192.168.66.190")
try:
    # ──── 1. 电机诊断 ────────────────────────────────────

    print("=== 电机诊断 ===")
    motors = dog.get_motor_status()

    online_count = sum(1 for m in motors if m.online)
    fault_count = sum(1 for m in motors if m.errors)
    print(f"在线: {online_count}/16, 故障: {fault_count}/16")

    for m in motors:
        status = "OK" if m.online and not m.errors else "FAULT"
        print(
            f"  [{m.id:2d}] {JOINT_NAMES[m.id]:10s}  "
            f"{status:5s}  "
            f"temp={m.temperature:4.0f}C  "
            f"V={m.voltage:5.1f}  "
            f"pos={m.position:+7.3f}rad  "
            f"vel={m.velocity:+7.3f}  "
            f"torque={m.torque:+6.2f}Nm"
        )

    # ──── 2. 电压检查 ────────────────────────────────────

    print("\n=== 电压检查 ===")
    voltages = dog.get_voltage()
    min_v = min(v for v in voltages if v > 0) if any(v > 0 for v in voltages) else 0
    max_v = max(voltages)
    print(f"电压范围: {min_v:.1f}V ~ {max_v:.1f}V")
    if min_v < 42.0:
        print(f"  WARNING: 最低电压 {min_v:.1f}V < 42.0V，请充电!")
    else:
        print(f"  电压正常 (阈值 42.0V)")

    # ──── 3. 故障处理 ────────────────────────────────────

    if fault_count > 0:
        print(f"\n=== 故障处理 ===")
        faulted = [m.id for m in motors if m.errors]
        print(f"故障关节: {[JOINT_NAMES[i] for i in faulted]}")

        response = input("是否清除故障？(y/n): ")
        if response.lower() == "y":
            dog.clear_motor_fault(faulted)
            print("故障已清除。")
            time.sleep(0.5)

            # 重新检查
            motors2 = dog.get_motor_status()
            still_faulted = [m.id for m in motors2 if m.errors]
            if still_faulted:
                print(f"  仍有故障: {[JOINT_NAMES[i] for i in still_faulted]}")
                print("  请检查硬件连接或重新上电。")
            else:
                print("  所有故障已清除!")

    # ──── 4. 标零（可选）───────────────────────────────────

    print("\n=== 标零 ===")
    state = dog.get_state()
    if state == "grounded":
        response = input("当前在 Grounded 状态，是否标零？(y/n): ")
        if response.lower() == "y":
            dog.set_zero()
            print("标零完成。当前位置已设为零点。")
    else:
        print(f"当前状态: {state}，标零需要在 Grounded 状态。")

    # ──── 5. 实时关节监控 ────────────────────────────────

    print("\n=== 实时关节监控 (5 秒) ===")
    dog.enable()
    dog.stand_up()
    time.sleep(1)

    count = 0
    try:
        for joint in dog.listen_joint():
            name = JOINT_NAMES[joint.id] if joint.id < 16 else f"Joint{joint.id}"
            print(
                f"  {name:10s}  "
                f"pos={joint.position:+7.3f}  "
                f"vel={joint.velocity:+7.3f}  "
                f"torque={joint.torque:+6.2f}",
                end="\r",
            )
            count += 1
            if count > 250:  # ~5 seconds at 50Hz
                break
    except KeyboardInterrupt:
        pass

    print("\n\n监控结束。")
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
