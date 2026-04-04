# Brainstem SDK for Python

Thunder 四足机器人 Python 开发套件。3 行代码控制机器人。

## 安装

```bash
cd sdk/python
pip install -e .
```

摄像头功能需要额外安装 opencv-python:

```bash
pip install -e ".[camera]"
```

## 快速开始

```python
from brainstem_sdk import ThunderClient

# 连接机器人 (默认 192.168.66.190:13145)
dog = ThunderClient("192.168.66.190")

# 使能电机 → 站起 → 走路 → 坐下 → 禁用
dog.enable()
dog.stand_up()
dog.walk(vx=0.3)       # 30% 速度前进
dog.walk(vx=0, vyaw=0.2)  # 原地左转
dog.sit_down()
dog.disable()
```

## API 参考

### 连接

```python
# 默认连接
dog = ThunderClient("192.168.66.190")

# 自定义端口和超时
dog = ThunderClient("10.0.0.1", port=13145, timeout=5.0)

# 支持 with 语句
with ThunderClient("192.168.66.190") as dog:
    dog.stand_up()

# 检查连接
if dog.ping():
    print("机器人在线")
```

### 运动控制

| 方法 | 说明 | 参数 |
|------|------|------|
| `dog.enable()` | 使能全部电机 | - |
| `dog.disable()` | 禁用全部电机 | - |
| `dog.stand_up()` | 坐姿 → 站立 | - |
| `dog.sit_down()` | 站立 → 坐姿 | - |
| `dog.walk(vx, vy, vyaw)` | 行走 | vx: 前后 [-1,1], vy: 左右 [-1,1], vyaw: 旋转 [-1,1] |

**walk() 参数约定：**
- `vx > 0` = 前进, `vx < 0` = 后退
- `vy > 0` = 向左, `vy < 0` = 向右
- `vyaw > 0` = 逆时针, `vyaw < 0` = 顺时针
- `dog.walk()` (无参数) = 原地停步

### 速度模式

```python
# 开启高速模式 (最高 2.5m/s，仅在开阔平坦场地使用)
dog.set_high_speed(True)

# 查询当前速度模式
mode = dog.get_speed_mode()  # "normal" 或 "high_speed"

# 关闭高速模式
dog.set_high_speed(False)
```

### 动作系统 (Gesture)

```python
# 列出所有预设动作
gestures = dog.list_gestures()
for g in gestures:
    print(f"{g.name}: {g.description} ({g.duration_ms}ms)")

# 播放动作 (机器人必须在 Standing 状态)
dog.play_gesture("bow")    # 鞠躬
dog.play_gesture("dance")  # 跳舞
```

### 摄像头 (OrixCamera)

需要安装 `pip install brainstem-sdk[camera]`。

```python
from brainstem_sdk import OrixCamera

# 上下文管理器 (推荐)
with OrixCamera() as cam:
    frame = cam.read()           # 读取一帧 (numpy BGR)
    cam.save_photo("photo.jpg")  # 拍照

# 远程 RTSP 流
cam = OrixCamera(source="rtsp://192.168.66.190:8554/cam")

# 启动 MJPEG 流服务器 (浏览器访问 http://<ip>:8080/)
cam.open()
cam.stream_mjpeg(port=8080)

# 录像
cam.start_recording("output.mp4", duration=10)
```

### 状态查询

```python
# 获取当前状态
state = dog.get_state()
# 返回: "zero" | "grounded" | "standing" | "walking" | "transitioning"

# 获取当前策略
profile = dog.get_profile()
print(profile.current)     # "default"
print(profile.available)   # ["default", "mini"]

# 切换策略 (机器人必须在 grounded 状态)
dog.switch_profile("mini")
```

### 诊断

```python
# 电压
voltages = dog.get_voltage()  # [42.1, 42.0, ...] 16个电机

# 电机状态
motors = dog.get_motor_status()
for m in motors:
    print(f"Joint {m.id}: online={m.online} temp={m.temperature}C")

# 清除电机故障
dog.clear_motor_fault()          # 清除全部
dog.clear_motor_fault([0, 1, 2]) # 只清前右腿

# 标零 (grounded 状态下)
dog.set_zero()
```

### 实时数据流

```python
# IMU 数据 (~50Hz)
for imu in dog.listen_imu():
    print(f"gyro: {imu.gyroscope.x:.3f}, {imu.gyroscope.y:.3f}, {imu.gyroscope.z:.3f}")
    print(f"quat: w={imu.quaternion.w:.3f}")

# 关节数据
for joint in dog.listen_joint():
    print(f"Joint {joint.id}: pos={joint.position:.3f} rad")

# 状态变化
for state in dog.listen_state():
    print(f"State changed: {state}")
```

## 关节编号

```
前右 (FR)           前左 (FL)
  0 Hip               4 Hip
  1 Thigh             5 Thigh
  2 Calf              6 Calf
  3 Foot              7 Foot

后右 (RR)           后左 (RL)
  8 Hip              12 Hip
  9 Thigh            13 Thigh
 10 Calf             14 Calf
 11 Foot             15 Foot
```

## 状态机

```
           Init
            │
            ▼
     ┌── Grounded ──┐
     │      ▲       │
     │      │       ▼
     │   SitDown  StandUp
     │      ▲       │
     │      │       ▼
     │   Standing ──┘
     │      │
     │      ▼
     └── Walking
```

- **Grounded**: 坐姿，安全状态。上电后自动进入。
- **Standing**: 站立，可以接收 walk 指令。
- **Walking**: 行走中。发送 `walk(0,0,0)` 回到 Standing。

## 示例

| 示例 | 说明 |
|------|------|
| `examples/01_hello_walk.py` | 最简走路示例 |
| `examples/02_read_imu.py` | 读取 IMU 数据流 |
| `examples/03_motor_diagnostics.py` | 电机诊断 |
| `examples/04_keyboard_control.py` | WASD 键盘控制 (Linux/macOS) |
| `examples/05_gestures.py` | 预设动作演示 |
| `examples/06_motor_control.py` | 电机操作全流程 |
| `examples/07_camera_basic.py` | 摄像头基础用法 |
| `examples/08_camera_record.py` | 摄像头录像 |
| `examples/09_camera_stream.py` | MJPEG 流服务器 |

## 网络要求

- 开发机和机器人在同一局域网
- 默认 gRPC 端口: **13145**
- 无需安装额外中间件（纯 gRPC over HTTP/2）

## 常见问题

**Q: 连接超时？**
确认机器人已开机且 brainstem 服务正在运行：
```bash
ssh sunrise@192.168.66.190
systemctl status brainstem
```

**Q: walk() 没反应？**
检查状态机：必须先 `stand_up()` 到 Standing 状态才能 walk。
```python
print(dog.get_state())  # 应该是 "standing"
```

**Q: 电机不动？**
1. 确认已调用 `dog.enable()`
2. 检查遥控器是否在线（遥控器优先级高于 gRPC）
3. 查看电机状态：`dog.get_motor_status()`
