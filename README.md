# brainstem

四足机器人控制系统。基于 ONNX 强化学习推理，支持真实硬件和 MuJoCo 仿真两种运行模式。

## 快速开始

```bash
# 安装依赖（需要 Flutter SDK，因为 workspace 含 sirius）
flutter pub get

# 代码检查（strict 模式）
dart analyze han_dog_brain/ han_dog/

# 运行测试（232 个）
dart test han_dog/ han_dog_brain/ frequency_watch/ skinny_dog_algebra/
```

### 新机器一键部署

```bash
sudo bash scripts/setup_brainstem.sh
```

自动完成：USB 串口驱动、CAN 接口自启、libcserialport 编译、libpcanbasic/libonnxruntime 链接、Dart SDK 检查。

### 真机运行

```bash
# 遥控器 + IMU + 电机全接好
HAN_DOG_IMU_PORT=/dev/imu dart run han_dog/bin/han_dog.dart

# 无遥控器（gRPC-only 模式，遥控器可选）
HAN_DOG_IMU_PORT=/dev/imu dart run han_dog/bin/han_dog.dart
```

### MuJoCo 仿真

```bash
# 终端 1: Dart server
ONNXRUNTIME_DLL_PATH=/path/to/libonnxruntime.so \
MEDULLA_PROFILE_DIR=han_dog/profiles \
MEDULLA_DEFAULT_PROFILE=thunder_h15 \
dart run han_dog/bin/server.dart

# 终端 2: MuJoCo 闭环测试
python sim/scripts/walk_grpc.py --profile han_dog/profiles/thunder_h15.json --height 0.32 --vx 0.3 --duration 5
```

### H15/H18 控制命令范围

H15 和 H18 使用相同的训练命令范围。gRPC 服务会按照当前 profile 对超出范围的命令逐轴截断：

| 命令 | gRPC 字段 | 有效范围 | 单位 |
|------|-----------|----------|------|
| 机身高度 | `SetBodyHeight.metres` | `0.20 .. 0.54` | m |
| 前后速度 | `Walk.x` / `vx` | `-2.5 .. 2.5` | m/s |
| 左右速度 | `Walk.y` / `vy` | `-1.0 .. 1.0` | m/s |
| 偏航角速度 | `Walk.z` / `yaw` | `-1.0 .. 1.0` | rad/s |

默认机身高度为 `0.35 m`。上述范围是训练包络和运行时硬限幅，不代表首次实机测试应直接使用边界值；首次体高验收建议保持零速度，并从 `0.35 m` 附近的小幅命令开始。

如果同一台机器人已经运行过 master 策略，且 CAN 接线、IMU 安装、关节零位、固件和遥控器安全链路均未改变，则 `bodyheightctrl` 只需做差异验证：H15/H18 模型与 profile 加载、`SetBodyHeight` 链路、零速度体高跟踪及小速度稳定性。只有硬件配置发生变化或出现异常时，才需要重新执行完整硬件检查。

体高策略接口、模型哈希、H15/H18 验证结果和真机安全门详见 [`docs/BODYHEIGHTCTRL.md`](docs/BODYHEIGHTCTRL.md)。

### 诊断工具

```bash
dart run han_dog/bin/ping.dart            # 16 电机连接检测
dart run han_dog/bin/calibrate_can.dart   # CAN 通道↔腿映射校准（手动转关节）
dart run han_dog/bin/ping_raw.dart        # 原始 4 路 CAN 全扫描
dart run han_dog/bin/test_grpc.dart       # gRPC 接口测试
```

---

## 代码结构

```
brainstem/
├── han_dog/                          ← 主程序包
│   ├── bin/
│   │   ├── han_dog.dart              ← 真机主程序（50Hz Timer 驱动）
│   │   ├── server.dart               ← 仿真主程序（MuJoCo gRPC 驱动）
│   │   ├── ping.dart                 ← 电机连接诊断
│   │   ├── ping_raw.dart             ← 原始 CAN 全扫描
│   │   ├── calibrate_can.dart        ← CAN↔腿映射校准
│   │   └── test_grpc.dart            ← gRPC 接口测试
│   ├── lib/src/
│   │   ├── app/                      ← 应用层（配置、监控、策略管理）
│   │   │   ├── config.dart           ←   环境变量配置
│   │   │   ├── profile_manager.dart  ←   策略热加载（每 30s 扫描）
│   │   │   ├── motor_health.dart     ←   电机健康管理（故障检测+恢复）
│   │   │   └── monitoring.dart       ←   传感器监控、调试 TUI
│   │   ├── server/                   ← gRPC 服务层
│   │   │   ├── unified_cms_server.dart ← 统一 gRPC 服务（仿真/硬件通用）
│   │   │   ├── gain_manager.dart     ←   PD 增益管理（按状态自动切换）
│   │   │   ├── proto_convert.dart    ←   Dart ↔ Protobuf 转换
│   │   │   └── sim_sensor.dart       ←   仿真传感器（SimSensorService）
│   │   ├── control_arbiter.dart      ← 控制权仲裁（遥控器优先级 > gRPC）
│   │   ├── real_control_dog.dart     ← YUNZHUO 遥控器桥接（速度强关联，无衰减）
│   │   ├── real_controller.dart      ← YUNZHUO 串口驱动（SBUS 协议）
│   │   ├── real_imu.dart             ← HI91 IMU 驱动（CP210x）
│   │   └── real_joint.dart           ← Robstride 电机驱动（PCAN/SocketCAN）
│   ├── profiles/                     ← 策略配置
│   │   ├── default.json              ←   默认策略（standingPose/kp/kd/modelPath）
│   │   └── mini.json                 ←   Mini Dog 策略
│   └── test/                         ← 测试
│
├── han_dog_brain/                    ← 推理核心（纯逻辑，无网络/硬件依赖）
│   ├── lib/src/
│   │   ├── brain.dart                ← Brain facade（外层只与它交互）
│   │   ├── cms/                      ← FSM 状态机（Zero→Grounded→Standing→Walking）
│   │   ├── behaviour.dart            ← 行为层（Walk/StandUp/SitDown/Idle/Gesture）
│   │   ├── observation_builder.dart  ← 57/58 维观测张量构建（与训练对齐）
│   │   ├── gesture.dart              ← 动作 SDK（关键帧插值、动作库）
│   │   ├── memory.dart               ← 策略相关长度的历史帧滑动窗口
│   │   ├── model_info.dart           ← ONNX 模型元数据推断
│   │   └── sensor.dart               ← 接口定义（ImuService/JointService）
│   └── test/
│
├── pcan/                             ← CAN 通信包
│   └── lib/src/
│       ├── pcan.dart                 ← 自动选择后端（PCAN Basic / SocketCAN）
│       ├── socketcan.dart            ← Linux SocketCAN 后端（AF_CAN socket）
│       ├── pcan_library.dart         ← PCAN Basic FFI 绑定
│       └── pcan_basic.dart           ← PCAN Basic API 封装
│
├── skinny_dog_algebra/               ← 数学库（JointsMatrix 16 关节矩阵）
├── onnx_runtime/                     ← ONNX 推理 FFI 绑定
├── serial_port/                      ← 串口通信（CSerialPort FFI）
├── robo_device/                      ← 设备抽象（PcanController/SerialPortController）
├── robo_device_proto/                ← 设备协议（Robstride/HiPNUC/YUNZHUO 编解码）
├── frequency_watch/                  ← 频率统计工具
├── han_dog_message/                  ← Protobuf/gRPC 协议（protoc 生成，勿手改）
├── protoframe/                       ← 帧协议解析
│
├── sim/                              ← MuJoCo 仿真
│   ├── robot/                        ← 机器人模型（URDF/XML/STL）
│   │   ├── quadruped.xml             ←   MuJoCo 模型
│   │   ├── quadruped.urdf            ←   URDF 模型
│   │   └── meshes/                   ←   STL 模型文件
│   ├── scripts/                      ← Python 仿真脚本
│   │   ├── verify_gestures.py        ←   动作验证（离线，不走 gRPC）
│   │   ├── walk_ref.py               ←   参考步态
│   │   ├── xbox_remote.py            ←   Xbox 手柄远程控制真机
│   │   └── xbox_config.py            ←   Xbox 配置工具
│   └── model/                        ← 仿真用 ONNX 策略
│
├── sirius/                           ← Flutter 桌面控制 App
├── scripts/                          ← 部署脚本
│   └── setup_brainstem.sh            ← 一键部署（新机器跑一次即可）
├── docs/                             ← 文档归档
│   ├── HANDOFF_CMS_APP_SYNC_*.md     ←   工作交接记录
│   └── sim_archive/                  ←   旧仿真脚本存档
├── _archive/                         ← 旧版代码/资源归档（untracked，不入 git）
└── CLAUDE.md                         ← AI 工作指南
```

---

## 架构

### 分层设计

```
┌─────────────────────────────────────────────────────┐
│  入口层                                              │
│  han_dog.dart（真机 50Hz）  server.dart（仿真 gRPC）  │
├─────────────────────────────────────────────────────┤
│  gRPC 服务层                                         │
│  UnifiedCmsServer · ControlArbiter · ProfileManager  │
├─────────────────────────────────────────────────────┤
│  硬件适配层                                          │
│  RealImu(Hi91) · RealJoint(Robstride) · RealController│
│  SimSensorService（仿真模式替代）                      │
├─────────────────────────────────────────────────────┤
│  推理核心（han_dog_brain，纯逻辑无硬件依赖）          │
│  Brain · FSM(M) · Behaviour · ObservationBuilder     │
│  Gesture SDK · Memory · ONNX Runtime                 │
├─────────────────────────────────────────────────────┤
│  通信层                                              │
│  pcan（PCAN Basic / SocketCAN 自动切换）              │
│  serial_port（CSerialPort FFI）                      │
├─────────────────────────────────────────────────────┤
│  基础层                                              │
│  skinny_dog_algebra · onnx_runtime · frequency_watch │
└─────────────────────────────────────────────────────┘
```

**核心原则**：Brain 不知道自己跑在真机还是仿真——所有硬件差异在传感器接口层隔离。

### 数据流

```
传感器 → ImuService/JointService
              ↓
ObservationBuilder.build(History) → 57/58 维 float[]
              ↓
      ONNX policy 推理 → 16 维 action
              ↓
   toRealAction(action) → 关节目标角度
              ↓
MotorService.sendAction() → CAN 总线 / MuJoCo
```

### 观测张量布局（57 维基础接口；体高策略为 58 维）

```
obs[0:3]   = gyroscope × 0.25          (body frame 角速度)
obs[3:6]   = projectedGravity          (body frame 重力投影)
obs[6:9]   = command [vx, vy, vyaw]    (速度命令)
obs[9:25]  = jointPosition - standing  (关节位置偏差，foot 归零)
obs[25:41] = jointVelocity × 0.05      (关节速度)
obs[41:57] = (lastAction - standing) / actionScale  (上一步动作)
obs[57]    = bodyHeightCommand in metres             (仅体高策略)
```

### FSM 状态转换

```
Zero ──Init──> Grounded ──StandUp──> Transitioning ──Done──> Standing
                   ^                                          │  ^
                   │ SitDown Done                       Walk  │  │ Gesture Done
                   │                                          v  │
              Transitioning(SitDown)                     Walking ─┘
```

---

## gRPC 接口

端口 `13145`，proto 定义在子模块 `brainstem_api/brainstem_api/cms.proto`。

### 运动控制

| RPC | 参数 | 说明 |
|-----|------|------|
| `Walk(Vector3)` | x=前后, y=左右, z=旋转 | 按当前策略的逐轴训练范围截断 |
| `SetBodyHeight(BodyHeightCommand)` | metres | 按当前策略体高范围截断 |
| `StandUp()` | - | 从坐姿站起 |
| `SitDown()` | - | 从站立坐下 |
| `Enable()` / `Disable()` | - | 电机使能/禁用 |

### 状态查询

| RPC | 返回 | 说明 |
|-----|------|------|
| `GetCmsState()` | CmsState | FSM 当前状态 |
| `ListenCmsState()` | stream CmsState | FSM 状态变化推送 |
| `GetProfile()` | ProfileInfo | 当前策略信息 |
| `SwitchProfile(name)` | ProfileInfo | 切换策略（Grounded 状态） |
| `GetStartTime()` | Timestamp | 服务启动时间 |
| `GetParams()` | Params | 机器人模型参数 |

### 传感器数据流

| RPC | 返回 | 频率 |
|-----|------|------|
| `ListenHistory()` | stream History | 50Hz（推理帧） |
| `ListenImu()` | stream Imu | ~100Hz |
| `ListenJoint()` | stream Joint | ~115Hz |

### 诊断接口

| RPC | 返回 | 说明 |
|-----|------|------|
| `GetVoltage()` | Voltage | 16 电机总线电压 (V) |
| `GetMotorStatus()` | MotorStatusResponse | 16 电机状态（在线/温度/力矩/故障码） |
| `ClearMotorFault(joint_ids)` | - | 清除电机故障（空=全部） |

### 仿真专用

| RPC | 说明 |
|-----|------|
| `Step(SimState)` | 注入传感器数据（MuJoCo → Dart） |
| `Tick()` → History | 触发一帧推理（Dart → MuJoCo） |

---

## 关节索引

所有 `Matrix4` 消息和 `JointsMatrix` 使用统一的 16 关节顺序：

```
 0 FR_hip     3 FL_hip     6 RR_hip     9 RL_hip
 1 FR_thigh   4 FL_thigh   7 RR_thigh  10 RL_thigh
 2 FR_calf    5 FL_calf    8 RR_calf   11 RL_calf
12 FR_foot   13 FL_foot   14 RR_foot   15 RL_foot
```

## 坐标约定

全链路统一，与 Isaac Lab 训练一致：

```
Body frame: X=前, Y=左, Z=上
Walk 命令: x>0 前进, y>0 向左, z>0 逆时针
四元数: Hi91 IMU 输出 → quaternion.rotate([0,0,-1]) = projected gravity
关节: Dart 值直接用（真机）; MuJoCo 需取反（dart_to_mujoco）
PD gains: 不取反（dart_gains_to_mujoco 只重排顺序）
```

---

## 遥控器

YUNZHUO 遥控器通过 SBUS 协议（CH340 USB 串口），udev 规则映射到 `/dev/yunzhuo`。

| 控件 | 功能 |
|------|------|
| 左摇杆 Y | 前后速度（前推=前进） |
| 左摇杆 X | 左右速度（左推=向左） |
| 旋钮 + 右摇杆 X | 偏航旋转 |
| CH5 (H) | 电机使能开关 |
| L1 | StandUp |
| L2 | SitDown |
| R1 | StandUp |
| R2 | 策略切换 |
| 红键 | 紧急停止（disable + clear errors） |
| LT | 精确模式（速度×0.5） |
| RT | 冲刺模式（速度×1.5） |

遥控器可选——未接时以 gRPC-only 模式启动。摇杆速度强关联：松手即归零，无衰减。

---

## 策略配置 (Profile)

`han_dog/profiles/*.json`：

```json
{
  "name": "default",
  "modelPath": "model/policy_260106.onnx",
  "standingPose": [-0.1, -0.8, 1.8, 0.1, 0.8, -1.8, ...],
  "sittingPose": [0, 0, 0, ...],
  "standUpCounts": 150,
  "sitDownCounts": 150,
  "inferKp": [65, 95, 120, 65, 95, 120, ...],
  "inferKd": [20, 20, 20, ...],
  "imuGyroscopeScale": 0.25,
  "jointVelocityScale": [0.05, 0.05, 0.05, 0.05],
  "actionScale": [0.125, 0.25, 0.25, 5.0]
}
```

支持运行时热切换（Grounded 状态下通过 gRPC `SwitchProfile` 或遥控器 R2）。

---

## 环境变量

### 真机 (`han_dog.dart`)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HAN_DOG_PORT` | `13145` | gRPC 端口 |
| `HAN_DOG_IMU_PORT` | `/dev/ttyUSB1` | IMU 串口（建议用 `/dev/imu`） |
| `HAN_DOG_YUNZHUO_PORT` | `/dev/yunzhuo` | 遥控器串口 |
| `HAN_DOG_PROFILE_DIR` | `han_dog/profiles` | 策略目录 |
| `HAN_DOG_DEFAULT_PROFILE` | (第一个) | 默认策略名 |
| `HAN_DOG_ARBITER_TIMEOUT` | `3` | 仲裁器超时（秒） |
| `HAN_DOG_STARTUP_TIMEOUT` | `10` | FSM 启动超时（秒） |
| `HAN_DOG_SHUTDOWN_TIMEOUT` | `8` | 关机超时（秒） |
| `HAN_DOG_LOG` | `INFO` | 日志级别 |

### 仿真 (`server.dart`)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MEDULLA_PORT` | `13145` | gRPC 端口 |
| `MEDULLA_PROFILE_DIR` | `han_dog/profiles` | 策略目录 |
| `MEDULLA_DEFAULT_PROFILE` | (第一个) | 默认策略名 |
| `MEDULLA_HISTORY_SIZE` | (自动推断) | 历史帧数 |
| `MEDULLA_LOG` | `INFO` | 日志级别 |
| `ONNXRUNTIME_DLL_PATH` | (系统搜索) | ONNX Runtime 动态库路径 |

---

## CAN 通信

pcan 包自动选择后端：
- **有 `/sys/class/pcan`**（chardev 驱动）→ PCAN Basic API
- **无 chardev**（SocketCAN 驱动）→ Linux AF_CAN socket

默认通道映射（`han_dog.dart`）：

```dart
RealJoint(fr: .usbbus3, fl: .usbbus1, rr: .usbbus4, rl: .usbbus2)
// usbbus1 → can0, usbbus2 → can1, usbbus3 → can2, usbbus4 → can3
```

使用 `calibrate_can.dart` 校准实际接线映射。

---

## 部署

### systemd 服务

`scripts/setup_brainstem.sh` 自动配置：

| 服务 | 说明 |
|------|------|
| `can-setup.service` | CAN 接口自启（1Mbps, txqueuelen 100） |
| `han_dog.service` | brainstem 主程序（需手动创建） |

### udev 规则

```
/dev/imu      → CP210x (Hi91 IMU)
/dev/yunzhuo  → CH340 (YUNZHUO 遥控器)
```

### 依赖

| 库 | 来源 | 说明 |
|----|------|------|
| `libcserialport.so` | 编译自 CSerialPort | IMU/遥控器串口 |
| `libpcanbasic.so` | PEAK 提供 | PCAN Basic（可选，SocketCAN 可替代） |
| `libonnxruntime.so` | pip onnxruntime 或手动安装 | ONNX 推理 |

---

## 动作 SDK（Gesture）

```dart
// 创建动作库
final gestureLib = GestureLibrary(standingPose: standingPose)
  ..registerDefaults();  // bow, nod, wiggle, stretch
brain.gestureLibrary = gestureLib;

// 触发动作（Standing 状态）
m.add(A.gesture('bow'));
```

支持 JSON 自定义动作、关键帧插值、余弦缓入缓出。

---

## 测试

```bash
dart test han_dog/              # ControlArbiter, RealControlDog, UnifiedCmsServer, ProtoConvert...
dart test han_dog_brain/        # FSM 全路径, Memory, Behaviour, ObservationBuilder, Gesture...
dart test frequency_watch/      # 频率统计
dart test skinny_dog_algebra/   # JointsMatrix, clamp, NaN 检测
```

全部 232 个测试必须通过。每次改动后运行 `dart analyze han_dog_brain/ han_dog/` 确保零 issue。

---

## 关键接口

推理核心通过接口与硬件解耦：

| 接口 | 真机实现 | 仿真实现 |
|------|---------|---------|
| `ImuService` | `RealImu` (Hi91) | `SimSensorService` |
| `JointService` | `RealJoint` (Robstride) | `SimSensorService` |
| `MotorService` | `RealJoint` | 不需要 |
| `SimStateInjector` | 不需要 | `SimSensorService` |
