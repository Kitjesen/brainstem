# ORIX SDK for Python

ORIX 教育版四足机器狗 Python 开发套件。3 行代码控制机器人。

## 安装

ORIX SDK 通过 Python 标准包管理工具 pip 安装。安装完成后，可在任何 Python 3.8+ 环境中使用。

```bash
cd sdk/python
pip install -e .
```

如果需要使用摄像头功能（拍照、录像、MJPEG 流），需额外安装 opencv-python：

```bash
pip install -e ".[camera]"
```

## 快速开始

以下示例展示了控制机器狗的最基本流程：连接、使能电机、站起、行走、坐下、禁用。所有操作通过 `OrixClient` 完成，您不需要了解底层通信协议。

```python
from brainstem_sdk import OrixClient

# 连接机器人 (默认 192.168.66.190:13145)
dog = OrixClient("192.168.66.190")

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

在使用任何控制指令前，需要先建立与机器狗主控板的网络连接。确保您的开发电脑与机器狗处于同一局域网。`OrixClient` 创建时会自动建立 gRPC 连接通道，使用 `ping()` 可以验证通信是否正常。推荐使用 `with` 语句，它会在进入时自动验证连接，退出时自动释放资源。

```python
# 默认连接
dog = OrixClient("192.168.66.190")

# 自定义端口和超时
dog = OrixClient("10.0.0.1", port=13145, timeout=5.0)

# 支持 with 语句（推荐，自动验证连接 + 资源释放）
with OrixClient("192.168.66.190") as dog:
    dog.stand_up()

# 手动检查连接
if dog.ping():
    print("机器人在线")
```

### 运动控制

ORIX 机器狗支持站立、坐下、行走三种基本运动。所有运动指令通过 `OrixClient` 发送，机器狗内置的状态机会自动管理运动状态转换。使能电机后，机器狗进入 Grounded（着地）状态，此时可以发送 `stand_up()` 站起，站立后即可发送 `walk()` 行走指令。

| 方法 | 说明 | 参数 |
|------|------|------|
| `dog.enable()` | 使能全部电机 | - |
| `dog.disable()` | 禁用全部电机 | - |
| `dog.stand_up()` | 着地 → 站立（约 3 秒过渡） | - |
| `dog.sit_down()` | 站立 → 着地（约 3 秒过渡） | - |
| `dog.walk(vx, vy, vyaw)` | 行走（需在站立状态） | 见下方说明 |

**walk() 参数约定：** 三个参数均为归一化速度，范围 [-1, 1]，SDK 会自动 clamp 超出范围的值。

- `vx > 0` = 前进, `vx < 0` = 后退
- `vy > 0` = 向左, `vy < 0` = 向右
- `vyaw > 0` = 逆时针, `vyaw < 0` = 顺时针
- `dog.walk()` (无参数) = 原地停步

### 速度模式

机器狗默认在标准速度模式下运行。开启高速模式后，最大行走速度可达 2.5m/s。高速模式仅应在开阔平坦的场地使用，开启前请确保周围无障碍物。

```python
# 开启高速模式 (最高 2.5m/s)
dog.set_high_speed(True)

# 查询当前速度模式
mode = dog.get_speed_mode()  # "normal" 或 "high_speed"

# 关闭高速模式，回到标准速度
dog.set_high_speed(False)
```

### 动作系统 (Gesture)

除了基本行走，机器狗内置了多种预设动作，如鞠躬、点头、扭动、伸展和跳舞。每个动作由一组关键帧定义，机器狗会平滑地在关键帧之间插值执行。播放动作前，机器狗必须处于站立（Standing）状态。

```python
# 列出所有预设动作及其描述
gestures = dog.list_gestures()
for g in gestures:
    print(f"{g.name}: {g.description} ({g.duration_ms}ms)")

# 播放动作 (机器人必须在 Standing 状态)
dog.play_gesture("bow")    # 鞠躬
dog.play_gesture("nod")    # 点头
dog.play_gesture("wiggle") # 扭动
dog.play_gesture("stretch") # 伸展
dog.play_gesture("dance")  # 跳舞
```

### 摄像头 (OrixCamera)

OrixCamera 提供对机器狗上 USB 摄像头的访问能力，支持拍照、录像和实时 MJPEG 流。摄像头模块是可选功能，需要额外安装 `pip install brainstem-sdk[camera]`。支持两种工作模式：本地模式（直接连接 USB 摄像头，在机器狗上运行）和远程模式（通过 RTSP/MJPEG URL 从网络读取）。

```python
from brainstem_sdk import OrixCamera

# 上下文管理器 (推荐，自动管理摄像头生命周期)
with OrixCamera() as cam:
    frame = cam.read()           # 读取一帧 (numpy BGR 格式)
    cam.save_photo("photo.jpg")  # 拍照保存

# 远程 RTSP 流（从开发机访问机器狗摄像头）
cam = OrixCamera(source="rtsp://192.168.66.190:8554/cam")

# 启动 MJPEG 流服务器（浏览器访问 http://<机器狗IP>:8080/）
cam.open()
cam.stream_mjpeg(port=8080)

# 录像（自动在 10 秒后停止）
cam.start_recording("output.mp4", duration=10)
```

### 状态查询

机器狗运行时维护一个有限状态机（FSM），您可以随时查询当前状态。状态查询不受控制权仲裁限制，任何已连接的客户端都可以读取。

```python
# 获取当前状态
state = dog.get_state()
# 返回: "zero" | "grounded" | "standing" | "walking" | "transitioning"
```

### 策略管理

策略（Profile）定义了机器狗的运动参数，包括站立姿态、PD 增益、ONNX 模型路径等。不同的策略对应不同的运动风格。例如 "default" 策略用于标准行走，"mini" 策略适配 Mini 机型。您可以在运行时查看和切换策略，切换时机器狗必须处于着地（Grounded）状态。策略文件使用 JSON 格式，存放在机器狗的 profiles/ 目录下，支持热加载（每 30 秒自动扫描变更）。

```python
# 查看当前策略和可用策略列表
profile = dog.get_profile()
print(f"当前策略: {profile.current}")
print(f"可用策略: {profile.available}")
print(f"策略说明: {profile.descriptions}")

# 切换策略（机器人必须在 grounded 状态）
dog.switch_profile("mini")
```

### 诊断

诊断接口用于检查电机健康状态、读取母线电压和清除故障码。在每次启动运动前进行诊断检查是良好的工程实践，可以提前发现硬件问题，避免运动中出现意外。

```python
# 读取 16 个电机的母线电压 (V)
voltages = dog.get_voltage()
print(f"电压范围: {min(voltages):.1f}V ~ {max(voltages):.1f}V")

# 查看每个电机的详细状态（在线状态、温度、位置、故障码）
motors = dog.get_motor_status()
for m in motors:
    print(f"Joint {m.id}: online={m.online} temp={m.temperature}C errors={m.errors}")

# 清除电机故障码
dog.clear_motor_fault()          # 清除全部
dog.clear_motor_fault([0, 1, 2]) # 只清指定关节

# 标零：将当前位置设为电机零点（机器人必须在 grounded 状态）
dog.set_zero()
```

### 实时数据流

SDK 提供三种实时数据订阅接口，均以 Python 迭代器方式返回。IMU 数据包含陀螺仪角速度和姿态四元数，更新频率约 50Hz。关节数据包含每个关节的位置、速度和力矩。状态流在机器狗状态发生变化时推送新状态。这些数据流可用于数据记录、实时监控和自定义控制算法开发。

```python
# IMU 数据 (~50Hz，包含陀螺仪和四元数)
for imu in dog.listen_imu():
    print(f"gyro: {imu.gyroscope.x:.3f}, {imu.gyroscope.y:.3f}, {imu.gyroscope.z:.3f}")
    print(f"quat: w={imu.quaternion.w:.3f}")

# 关节数据（位置 rad、速度 rad/s、力矩 Nm）
for joint in dog.listen_joint():
    print(f"Joint {joint.id}: pos={joint.position:.3f} rad")

# 状态变化订阅
for state in dog.listen_state():
    print(f"State changed: {state}")
```

## 关节编号

机器狗共有 16 个自由度：4 条腿各 3 个关节（髋关节、大腿、小腿）加 1 个足轮。关节编号在整个 SDK 中保持一致，从 0 开始。

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

机器狗通过有限状态机（FSM）管理运动状态。上电后自动进入 Grounded（着地）状态，这是最安全的状态。状态转换遵循固定的路径：着地 → 站立 → 行走，反向同理。发送不符合当前状态的指令会被静默忽略（不会报错），确保安全。

- **Grounded（着地）**: 四腿折叠收拢，躯干贴地。上电后的默认状态，也是关机前的安全姿态。
- **Standing（站立）**: 四腿伸展支撑，可以接收 walk 指令和播放动作。
- **Walking（行走）**: 执行 RL 策略推理，按 walk() 指定的方向行走。发送 `walk(0,0,0)` 停步回到 Standing。
- **Transitioning（过渡中）**: 站起或坐下的中间状态，约 3 秒，此时不接受新指令。

## 错误处理

SDK 提供了友好的异常类，将底层 gRPC 错误映射为易于理解的 Python 异常。所有异常继承自 `OrixError`。

| 异常 | 含义 | 常见原因 |
|------|------|---------|
| `OrixConnectionError` | 无法连接机器人 | IP 错误、机器人未开机、网络不通 |
| `InvalidStateError` | 机器人状态不对 | 在着地状态发 walk、在行走中切策略 |
| `OrixTimeoutError` | 操作超时 | 网络延迟、机器人负载过高 |
| `OrixError` | 其他错误 | gRPC 层面的未预期错误 |

```python
from brainstem_sdk import OrixClient, OrixConnectionError, InvalidStateError

try:
    with OrixClient("192.168.66.190") as dog:
        dog.stand_up()
        dog.walk(vx=0.5)
except OrixConnectionError:
    print("无法连接机器人，请检查网络")
except InvalidStateError as e:
    print(f"状态错误: {e}")
```

## 示例

| 示例 | 说明 |
|------|------|
| `examples/01_hello_walk.py` | 最简走路示例 |
| `examples/02_read_imu.py` | 读取 IMU 数据流 |
| `examples/03_motor_diagnostics.py` | 电机诊断 |
| `examples/04_keyboard_control.py` | WASD 键盘控制 (Linux/macOS) |
| `examples/05_gestures.py` | 预设动作演示 (鞠躬/点头/跳舞) |
| `examples/06_motor_control.py` | 电机操作全流程 (诊断/清错/标零/监控) |
| `examples/07_camera_basic.py` | 摄像头实时预览 + 拍照 |
| `examples/08_camera_record.py` | 摄像头录像 |
| `examples/09_camera_stream.py` | MJPEG 流服务器 (浏览器远程查看) |

## 网络要求

- 开发机和机器人在同一局域网
- 默认 gRPC 端口: **13145**
- 无需安装额外中间件（纯 gRPC over HTTP/2）

## 常见问题

**Q: 连接超时？**
确认机器人已开机且控制服务正在运行：
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
2. 检查遥控器是否在线（遥控器优先级高于 SDK 指令，3 秒无操作后自动释放控制权）
3. 查看电机状态：`dog.get_motor_status()`

**Q: 摄像头打不开？**
1. 确认已安装 `pip install brainstem-sdk[camera]`
2. 检查 USB 摄像头是否连接：`ls /dev/video*`
3. 确认没有其他程序占用摄像头
