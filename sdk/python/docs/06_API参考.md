# 06 -- API 参考

本章提供 ORIX Python SDK (`brainstem_sdk`) 全部公开接口的完整参考。

---

## 目录

1. [OrixClient 构造与连接](#1-thunderclient-构造与连接)
2. [电机控制](#2-电机控制)
3. [运动指令](#3-运动指令)
4. [状态查询](#4-状态查询)
5. [策略管理](#5-策略管理)
6. [诊断与标定](#6-诊断与标定)
7. [实时数据流](#7-实时数据流)
8. [数据类型参考](#8-数据类型参考)
9. [错误处理](#9-错误处理)

---

## 1. OrixClient 构造与连接

### 构造函数

```python
OrixClient(host="192.168.66.190", port=13145, timeout=5.0)
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `host` | str | `"192.168.66.190"` | 机器人 IP 地址 |
| `port` | int | `13145` | gRPC 服务端口 |
| `timeout` | float | `5.0` | 默认 RPC 超时时间（秒） |

**说明**：构造函数创建一个 gRPC 不安全通道（insecure channel），连接到 `host:port`。通道创建即连接，无需额外调用。

```python
from brainstem_sdk import OrixClient

# 默认连接
dog = OrixClient("192.168.66.190")

# 自定义参数
dog = OrixClient("10.0.0.100", port=13145, timeout=10.0)
```

### close()

```python
dog.close() -> None
```

关闭 gRPC 通道，释放网络资源。关闭后不可再调用任何方法。

### 上下文管理器

`OrixClient` 支持 `with` 语句，退出时自动调用 `close()`：

```python
with OrixClient("192.168.66.190") as dog:
    dog.enable()
    dog.stand_up()
    dog.walk(vx=0.3)
    dog.sit_down()
    dog.disable()
# 退出 with 块后通道自动关闭
```

---

## 2. 电机控制

### enable()

```python
dog.enable() -> None
```

使能全部 16 个电机。调用后电机通电并进入闭环控制。

| 项目 | 说明 |
|------|------|
| 前置条件 | gRPC 连接正常，控制权未被遥控器占用 |
| 异常 | `grpc.RpcError` -- 超时或连接失败 |

```python
dog.enable()
```

### disable()

```python
dog.disable() -> None
```

禁用全部电机（安全停止）。电机断电，关节自由落体。

| 项目 | 说明 |
|------|------|
| 前置条件 | 无（任何状态下均可调用） |
| 建议 | 在 Grounded 状态下调用，避免机器人从站立姿态跌落 |
| 异常 | `grpc.RpcError` -- 超时或连接失败 |

```python
# 安全关机序列
dog.walk(vx=0.0)   # 停步
dog.sit_down()      # 坐下
# 等待机器人坐稳...
dog.disable()       # 禁用电机
```

---

## 3. 运动指令

### walk()

```python
dog.walk(vx=0.0, vy=0.0, vyaw=0.0) -> None
```

发送行走速度指令。

| 参数 | 类型 | 默认值 | 范围 | 说明 |
|------|------|--------|------|------|
| `vx` | float | `0.0` | [-1.0, 1.0] | 前后速度。正值=前进，负值=后退 |
| `vy` | float | `0.0` | [-1.0, 1.0] | 左右速度。正值=向左，负值=向右 |
| `vyaw` | float | `0.0` | [-1.0, 1.0] | 旋转速度。正值=逆时针，负值=顺时针 |

| 项目 | 说明 |
|------|------|
| 前置条件 | 机器人处于 Standing 或 Walking 状态 |
| 停步 | 调用 `dog.walk()` 或 `dog.walk(0, 0, 0)` |
| 异常 | `grpc.RpcError` -- 超时、连接失败或 Arbiter 拒绝 |

**速度参数为归一化值**，不是物理速度。`vx=1.0` 表示当前策略允许的最大前进速度，实际物理速度取决于所加载的运动策略。

```python
# 前进
dog.walk(vx=0.5)

# 向左平移
dog.walk(vy=0.3)

# 前进 + 左转
dog.walk(vx=0.3, vyaw=0.2)

# 原地停步
dog.walk()
```

### stand_up()

```python
dog.stand_up() -> None
```

从坐姿过渡到站立。

| 项目 | 说明 |
|------|------|
| 前置条件 | 机器人处于 Grounded 状态，电机已使能 |
| 状态变化 | Grounded -> Transitioning -> Standing |
| 异常 | `grpc.RpcError` -- 超时或连接失败 |

### sit_down()

```python
dog.sit_down() -> None
```

从站立过渡到坐姿。如果正在行走，会先停步再坐下。

| 项目 | 说明 |
|------|------|
| 前置条件 | 机器人处于 Standing 或 Walking 状态 |
| 状态变化 | Standing/Walking -> Transitioning -> Grounded |
| 异常 | `grpc.RpcError` -- 超时或连接失败 |

---

## 4. 状态查询

### get_state()

```python
dog.get_state() -> str
```

查询当前机器人状态。

| 返回值 | 说明 |
|--------|------|
| `"zero"` | 初始化 / 未使能 |
| `"grounded"` | 坐姿（安全状态） |
| `"standing"` | 站立，可接收行走指令 |
| `"walking"` | 行走中 |
| `"transitioning"` | 状态过渡中（站起 / 坐下） |

```python
state = dog.get_state()
print(f"当前状态: {state}")

if state == "standing":
    dog.walk(vx=0.3)
```

### get_voltage()

```python
dog.get_voltage() -> list[float]
```

读取 16 个电机的母线电压。

| 项目 | 说明 |
|------|------|
| 返回值 | 长度为 16 的浮点数列表，单位 V |
| 索引 | 对应关节编号 0-15 |
| 低压阈值 | 18V，低于此值系统自动触发保护 |

```python
voltages = dog.get_voltage()
print(f"最低电压: {min(voltages):.1f}V")
```

### get_motor_status()

```python
dog.get_motor_status() -> list[MotorInfo]
```

获取全部 16 个电机的健康状态。

| 项目 | 说明 |
|------|------|
| 返回值 | 长度为 16 的 `MotorInfo` 列表 |
| 包含 | 在线状态、温度、电压、位置、速度、力矩、故障码 |

```python
motors = dog.get_motor_status()
for m in motors:
    if not m.online:
        print(f"Joint {m.id} 离线!")
    if m.errors:
        print(f"Joint {m.id} 故障: {m.errors}")
    if m.temperature > 70:
        print(f"Joint {m.id} 温度偏高: {m.temperature}C")
```

---

## 5. 策略管理

### get_profile()

```python
dog.get_profile() -> ProfileInfo
```

获取当前运动策略信息及可用策略列表。

| 项目 | 说明 |
|------|------|
| 返回值 | `ProfileInfo` 对象 |

```python
profile = dog.get_profile()
print(f"当前策略: {profile.current}")
print(f"可用策略: {profile.available}")
for name, desc in zip(profile.available, profile.descriptions):
    print(f"  {name}: {desc}")
```

### switch_profile()

```python
dog.switch_profile(name: str) -> ProfileInfo
```

切换运动策略。

| 参数 | 类型 | 说明 |
|------|------|------|
| `name` | str | 目标策略名称，必须在 `get_profile().available` 列表中 |

| 项目 | 说明 |
|------|------|
| 前置条件 | 机器人处于 **Grounded** 状态 |
| 返回值 | 切换后的 `ProfileInfo` |
| 异常 | `grpc.RpcError` -- 策略不存在、状态不对或超时 |

```python
# 查看可用策略
profile = dog.get_profile()
print(f"可用: {profile.available}")

# 切换策略（必须先坐下）
dog.sit_down()
# 等待 Grounded ...
new_profile = dog.switch_profile("thunder2v1")
print(f"已切换到: {new_profile.current}")
```

---

## 6. 诊断与标定

### clear_motor_fault()

```python
dog.clear_motor_fault(joint_ids=None) -> None
```

清除电机故障码。

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `joint_ids` | list[int] \| None | `None` | 要清除的关节编号列表 (0-15)。`None` 表示清除全部 |

```python
# 清除所有电机故障
dog.clear_motor_fault()

# 只清除前右腿
dog.clear_motor_fault(joint_ids=[0, 1, 2, 3])

# 只清除单个关节
dog.clear_motor_fault(joint_ids=[5])
```

### set_zero()

```python
dog.set_zero() -> None
```

将当前关节位置标定为零位。

| 项目 | 说明 |
|------|------|
| 前置条件 | 机器人处于 **Grounded** 状态 |
| 用途 | 出厂标定或维修后重新校准零位 |
| 注意 | 错误的零位会导致运动异常，非必要不调用 |

```python
# 确保在 Grounded 状态下执行
state = dog.get_state()
if state == "grounded":
    dog.set_zero()
    print("零位标定完成。")
else:
    print(f"当前状态 {state}，请先坐下。")
```

---

## 7. 实时数据流

所有 `listen_*` 方法返回 Python 迭代器（`Iterator`），底层为 gRPC 服务端流。迭代器在以下情况终止：

- 手动 `break`
- 键盘中断 (`Ctrl+C`)
- 调用 `dog.close()` 关闭通道
- 网络断开

### listen_imu()

```python
dog.listen_imu() -> Iterator[ImuData]
```

订阅 IMU 实时数据流，约 50Hz。

| 项目 | 说明 |
|------|------|
| 产出 | `ImuData`（含 `gyroscope`, `quaternion`, `timestamp_ms`） |
| 频率 | ~50 Hz |
| 阻塞 | 是（在 `for` 循环中阻塞等待下一帧） |

```python
for imu in dog.listen_imu():
    print(f"gyro=({imu.gyroscope.x:.3f}, {imu.gyroscope.y:.3f}, {imu.gyroscope.z:.3f})")
    print(f"quat=({imu.quaternion.w:.3f}, {imu.quaternion.x:.3f}, "
          f"{imu.quaternion.y:.3f}, {imu.quaternion.z:.3f})")
```

### listen_joint()

```python
dog.listen_joint() -> Iterator[JointData]
```

订阅关节实时数据流。

| 项目 | 说明 |
|------|------|
| 产出 | `JointData`（含 `id`, `position`, `velocity`, `torque`, `status`） |
| 频率 | ~50 Hz（逐关节上报） |
| 阻塞 | 是 |

```python
for joint in dog.listen_joint():
    print(f"Joint {joint.id}: pos={joint.position:+.3f} rad")
```

### listen_state()

```python
dog.listen_state() -> Iterator[str]
```

订阅状态机变化事件。仅在状态切换时产出，不定频。

| 项目 | 说明 |
|------|------|
| 产出 | 状态字符串：`"zero"`, `"grounded"`, `"standing"`, `"walking"`, `"transitioning"` |
| 频率 | 事件驱动（仅状态变化时触发） |
| 阻塞 | 是 |

```python
for state in dog.listen_state():
    print(f"状态变化: {state}")
    if state == "grounded":
        print("机器人已坐下。")
```

---

## 8. 数据类型参考

### Vec3

三维向量。

```python
@dataclass
class Vec3:
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
```

### Quat

四元数（Hamilton 约定：w, x, y, z）。

```python
@dataclass
class Quat:
    w: float = 1.0    # 实部
    x: float = 0.0    # 虚部 i
    y: float = 0.0    # 虚部 j
    z: float = 0.0    # 虚部 k
```

### ImuData

IMU 惯性测量数据帧。

```python
@dataclass
class ImuData:
    gyroscope: Vec3       # 角速度 (rad/s)
    quaternion: Quat      # 姿态四元数 (Hamilton w,x,y,z)
    timestamp_ms: float   # 时间戳 (ms)
```

### JointData

单个关节的实时数据。

```python
@dataclass
class JointData:
    id: int            # 关节编号 (0-15)
    position: float    # 角位置 (rad)
    velocity: float    # 角速度 (rad/s)
    torque: float      # 力矩 (Nm)
    status: int        # 状态码 (0=正常)
```

### MotorInfo

电机完整健康状态。

```python
@dataclass
class MotorInfo:
    id: int              # 关节编号 (0-15)
    online: bool         # 是否在线
    temperature: float   # 温度 (C)
    voltage: float       # 母线电压 (V)
    position: float      # 编码器位置 (rad)
    velocity: float      # 转速 (rad/s)
    torque: float        # 输出力矩 (Nm)
    errors: list[int]    # 故障码列表 (空=无故障)
```

### ProfileInfo

运动策略信息。

```python
@dataclass
class ProfileInfo:
    current: str           # 当前激活的策略名称
    available: list[str]   # 所有可用策略名称
    descriptions: list[str] # 各策略说明文字
```

### RobotState

状态机常量（字符串）。

```python
class RobotState:
    ZERO = "zero"
    GROUNDED = "grounded"
    STANDING = "standing"
    WALKING = "walking"
    TRANSITIONING = "transitioning"
```

使用方式：

```python
from brainstem_sdk import RobotState

state = dog.get_state()
if state == RobotState.STANDING:
    dog.walk(vx=0.3)
```

---

## 9. 错误处理

所有 RPC 调用可能抛出 `grpc.RpcError`。以下是常见错误场景及处理方式：

### 9.1 连接超时

```python
import grpc

try:
    dog = OrixClient("192.168.66.190", timeout=3.0)
    dog.get_state()
except grpc.RpcError as e:
    if e.code() == grpc.StatusCode.UNAVAILABLE:
        print("无法连接到机器人。请检查：")
        print("  1. 机器人是否已开机")
        print("  2. IP 地址是否正确")
        print("  3. brainstem 服务是否正在运行")
    elif e.code() == grpc.StatusCode.DEADLINE_EXCEEDED:
        print("请求超时。网络可能不稳定。")
    else:
        print(f"gRPC 错误: {e.code()} - {e.details()}")
```

### 9.2 常见错误码

| gRPC 状态码 | 含义 | 常见原因 |
|-------------|------|----------|
| `UNAVAILABLE` | 服务不可达 | 机器人未开机、IP 错误、服务未启动 |
| `DEADLINE_EXCEEDED` | 请求超时 | 网络延迟、服务端无响应 |
| `FAILED_PRECONDITION` | 前置条件不满足 | 状态不对（如在 Zero 状态下调用 walk） |
| `PERMISSION_DENIED` | 权限被拒 | Arbiter 控制权被遥控器占用 |
| `INTERNAL` | 服务端内部错误 | 硬件异常或程序错误 |

### 9.3 Arbiter 控制权冲突

Thunder 的控制仲裁器（ControlArbiter）确保遥控器始终具有最高优先级。当遥控器在线时，gRPC 指令可能被拒绝：

- 遥控器在线且正在操作：gRPC 运动指令将被忽略
- 遥控器在线但空闲超过 3 秒：gRPC 自动获得控制权
- 遥控器离线：gRPC 始终拥有控制权

```python
import grpc
import time

def safe_walk(dog, vx=0.0, vy=0.0, vyaw=0.0, retries=3):
    """带重试的行走指令。"""
    for attempt in range(retries):
        try:
            dog.walk(vx=vx, vy=vy, vyaw=vyaw)
            return True
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.PERMISSION_DENIED:
                print(f"控制权被遥控器占用，等待 ({attempt+1}/{retries})...")
                time.sleep(1.0)
            else:
                raise
    print("无法获得控制权。请确认遥控器已松开操控杆。")
    return False
```

### 9.4 流式接口异常处理

```python
try:
    for imu in dog.listen_imu():
        # 处理数据...
        pass
except grpc.RpcError as e:
    if e.code() == grpc.StatusCode.UNAVAILABLE:
        print("连接断开，尝试重连...")
    else:
        print(f"流异常: {e.code()}")
except KeyboardInterrupt:
    print("用户中断。")
finally:
    dog.close()
```

---

## 附录：方法速查表

| 分类 | 方法 | 返回值 | 说明 |
|------|------|--------|------|
| **连接** | `OrixClient(host, port, timeout)` | - | 构造并连接 |
| | `close()` | None | 关闭连接 |
| **电机** | `enable()` | None | 使能全部电机 |
| | `disable()` | None | 禁用全部电机 |
| **运动** | `walk(vx, vy, vyaw)` | None | 行走指令 |
| | `stand_up()` | None | 坐姿 -> 站立 |
| | `sit_down()` | None | 站立 -> 坐姿 |
| **状态** | `get_state()` | str | 查询 FSM 状态 |
| | `get_voltage()` | list[float] | 16 路母线电压 |
| | `get_motor_status()` | list[MotorInfo] | 16 个电机健康状态 |
| **策略** | `get_profile()` | ProfileInfo | 当前策略信息 |
| | `switch_profile(name)` | ProfileInfo | 切换运动策略 |
| **诊断** | `clear_motor_fault(joint_ids)` | None | 清除电机故障 |
| | `set_zero()` | None | 标定零位 |
| **数据流** | `listen_imu()` | Iterator[ImuData] | IMU 实时流 |
| | `listen_joint()` | Iterator[JointData] | 关节实时流 |
| | `listen_state()` | Iterator[str] | 状态变化流 |
