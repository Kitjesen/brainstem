"""读取 IMU 实时数据流。"""

from brainstem_sdk import ThunderClient

dog = ThunderClient("192.168.66.190")

print("订阅 IMU 数据 (Ctrl+C 退出)...")
try:
    for imu in dog.listen_imu():
        print(
            f"gyro=({imu.gyroscope.x:+.3f}, {imu.gyroscope.y:+.3f}, {imu.gyroscope.z:+.3f})  "
            f"quat=({imu.quaternion.w:.3f}, {imu.quaternion.x:.3f}, {imu.quaternion.y:.3f}, {imu.quaternion.z:.3f})  "
            f"t={imu.timestamp_ms:.0f}ms",
            end="\r",
        )
except KeyboardInterrupt:
    print("\n停止。")
finally:
    dog.close()
