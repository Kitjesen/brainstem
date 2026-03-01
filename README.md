# brainstem

四足机器人控制系统。基于 ONNX 强化学习推理，支持真实硬件和 MuJoCo 仿真两种运行模式。

## 快速开始

```bash
# 安装依赖
dart pub get

# 代码检查
dart analyze

# 运行测试（131 个）
dart test han_dog_brain/ han_dog/ frequency_watch/ skinny_dog_algebra/
```

### 真机运行

```bash
dart run han_dog/bin/han_dog.dart
```

### 仿真运行（MuJoCo）

```bash
dart run han_dog/bin/server.dart
```

MuJoCo Python 端通过 gRPC 调用 `step()` 注入传感器数据、调用 `tick()` 触发推理。

---

## 代码结构

```
brainstem/
│
├── han_dog/                          ← 主程序包（所有可运行入口都在这里）
│   ├── bin/
│   │   ├── han_dog.dart              ← ★ 真机主程序（接硬件跑这个）
│   │   └── server.dart               ← ★ 仿真主程序（MuJoCo 连这个）
│   ├── lib/src/
│   │   ├── app/                      ← 应用层
│   │   │   ├── config.dart           ←   环境变量配置
│   │   │   ├── robot_params.dart     ←   机器人参数（kp/kd、站立姿态）
│   │   │   └── monitoring.dart       ←   传感器监控、遥控器断连检测、调试 TUI
│   │   ├── server/                   ← gRPC 服务层
│   │   │   ├── unified_cms_server.dart ← gRPC 服务（仿真/硬件通用）
│   │   │   ├── gain_manager.dart     ←   PD 增益管理（按指令自动切换）
│   │   │   ├── proto_convert.dart    ←   Dart ↔ Protobuf 转换
│   │   │   └── sim_sensor.dart       ←   仿真传感器实现
│   │   ├── control_arbiter.dart      ← 控制权仲裁（遥控器 vs App）
│   │   ├── real_control_dog.dart     ← YUNZHUO 遥控器桥接
│   │   ├── real_controller.dart      ← YUNZHUO 串口驱动
│   │   ├── real_imu.dart             ← HI91 IMU 驱动
│   │   └── real_joint.dart           ← PCAN 关节电机驱动
│   └── test/                         ← 71 个测试
│
├── han_dog_brain/                    ← 推理核心（纯逻辑，不碰硬件）
│   ├── lib/src/
│   │   ├── brain.dart                ← Brain 总入口
│   │   ├── cms/                      ← FSM 状态机
│   │   │   ├── cms.dart              ←   状态转换逻辑
│   │   │   ├── s.dart                ←   状态定义
│   │   │   └── a.dart                ←   动作定义
│   │   ├── behaviour.dart            ← 行为层（Walk/StandUp/SitDown/Idle/Gesture）
│   │   ├── gesture.dart              ← ★ 动作 SDK（关键帧、动作库、预定义动作）
│   │   ├── memory.dart               ← 历史环形缓冲区
│   │   └── sensor.dart               ← 接口定义（ImuService/JointService 等）
│   └── test/                         ← 42 个测试
│
├── skinny_dog_algebra/               ← 数学库（JointsMatrix 16 关节矩阵）
├── onnx_runtime/                     ← ONNX 推理 FFI 绑定
├── frequency_watch/                  ← 频率统计工具
└── han_dog_message/                  ← Protobuf/gRPC 协议（protoc 生成，勿手改）
```

---

## 架构

### 分层设计

```
┌─────────────────────────────────────────────────────┐
│  应用层 (han_dog/bin/)                               │
│  han_dog.dart（真机）  server.dart（仿真）            │
├─────────────────────────────────────────────────────┤
│  服务层 (han_dog/lib/src/server/)                    │
│  UnifiedCmsServer · GainManager · proto_convert      │
├─────────────────────────────────────────────────────┤
│  硬件适配层 (han_dog/lib/src/)                       │
│  RealImu · RealJoint · RealController · SimSensor    │
├─────────────────────────────────────────────────────┤
│  推理核心 (han_dog_brain/)                           │
│  Brain · FSM(M) · Behaviour · Gesture · Memory       │
├─────────────────────────────────────────────────────┤
│  基础层                                              │
│  skinny_dog_algebra · onnx_runtime · frequency_watch │
└─────────────────────────────────────────────────────┘
```

关键原则：**han_dog_brain 是纯逻辑包**，不依赖 gRPC、Protobuf、硬件驱动。所有网络和硬件相关代码在 han_dog 包中。

### 数据流

```
YUNZHUO 遥控器 → RealControlDog → ControlArbiter → FSM(M) → Brain → 电机
App 远程控制   → UnifiedCmsServer → ControlArbiter ↗       ↑
                                                   ONNX 推理 (Walk)
                                                   或 Lerp 插值 (StandUp/SitDown)
```

遥控器（YUNZHUO）永远有最高优先权。App 通过 gRPC 发送的命令在遥控器操作时会被拒绝。

### FSM 状态转换

```
Zero ──Init──► Grounded ──StandUp──► Transitioning(StandUp) ──Done──► Standing
                                                                        │  ▲  ▲
                                                         SitDown        │  │  │ Gesture Done
                                                           ▼            │  │  │
                                                    Transitioning(SitDown) │ Transitioning(Gesture)
                                                           │            │     ▲
                                                         Done    Walking │     │ Gesture
                                                           ▼       ▲    │     │
                                                       Grounded    Walk ──────┘
```

安全保护：
- `Fault` 在任何运动状态下触发 → 自动坐下回到 Grounded
- Gesture 途中 Fault → 回到 Standing
- Ctrl-C 关机 → 安全坐下 → 禁用电机 → 释放资源

---

## gRPC 服务

`UnifiedCmsServer` 是唯一的 gRPC 服务实现，通过运行模式和依赖注入区分行为：

| 模式 | 用途 | tick/step | ControlArbiter |
|------|------|-----------|:-:|
| `CmsMode.simulation` | MuJoCo 仿真 | 可用 | 无 |
| `CmsMode.hardware` | 真实硬件 | 不可用 | 有 |

### RPC 接口

| RPC | 说明 |
|-----|------|
| `enable` / `disable` | 使能/禁用电机 |
| `walk(Vector3)` | 行走（方向向量） |
| `standUp` / `sitDown` | 站起/坐下 |
| `tick` | 触发一帧推理（仿真模式） |
| `step(SimState)` | 注入传感器数据（仿真模式） |
| `listenHistory` | 流式推理历史 |
| `listenImu` | 流式 IMU 数据 |
| `listenJoint` | 流式关节数据 |
| `getParams` | 获取机器人参数 |
| `getStartTime` | 获取启动时间 |

### SDK 集成示例

**仿真模式（MuJoCo / Python 调用）：**

```dart
final sim = SimSensorService(standingPose: standingPose);
final brain = Brain(imu: sim, joint: sim, clock: clock, ...);
final m = M(brain)..add(Init());

final server = UnifiedCmsServer(
  brain: brain,
  m: m,
  mode: CmsMode.simulation,
  simInjector: sim,
  gains: GainManager(
    inferKp: kp, inferKd: kd,
    standUpKp: standUpKp, standUpKd: standUpKd,
    sitDownKp: sitDownKp, sitDownKd: sitDownKd,
  ),
);
```

**硬件模式（真实机器人）：**

```dart
final server = UnifiedCmsServer(
  brain: brain,
  m: m,
  mode: CmsMode.hardware,
  arbiter: arbiter,
  imuStreamFactory: () => imuHardwareStream,
  jointStreamFactory: () => jointHardwareStream,
);
```

---

## 动作 SDK（Gesture）

机器人可以执行预定义的花式动作（鞠躬、点头、扭动、伸展等）。动作系统基于关键帧插值，支持自定义。

### 内置动作

| 名称 | 说明 | 关键帧数 |
|------|------|---------|
| `bow` | 鞠躬 / 拜年 | 3（弯下→保持→站回） |
| `nod` | 点头 | 4（低→高→低→高） |
| `wiggle` | 左右扭动 | 5（左→右→左→右→复位） |
| `stretch` | 伸展 | 4（前伸→复位→后伸→复位） |

### 使用方式

```dart
// 1. 创建动作库并注册内置动作
final gestureLib = GestureLibrary(standingPose: standingPose)
  ..registerDefaults();

// 2. 挂载到 Brain
brain.gestureLibrary = gestureLib;

// 3. 通过 FSM 触发（机器人必须在 Standing 状态）
m.add(A.gesture('bow'));

// 或通过 UnifiedCmsServer
server.gesture('bow');
```

### 自定义动作

```dart
// 通过代码定义
gestureLib.register(GestureDefinition(
  name: 'dance',
  description: '跳舞',
  keyframes: [
    Keyframe(targetPose: pose1, counts: 30),  // 30 帧插值到 pose1
    Keyframe(targetPose: pose2, counts: 20),  // 20 帧插值到 pose2
    Keyframe(targetPose: standingPose, counts: 40), // 回到站立
  ],
));

// 通过 JSON 加载
gestureLib.loadFromJson(jsonString);
```

### JSON 格式

```json
[
  {
    "name": "wave",
    "description": "挥手",
    "keyframes": [
      { "targetPose": [0, -0.8, 1.8, ...], "counts": 30 },
      { "targetPose": [0, -0.4, 1.2, ...], "counts": 30 }
    ]
  }
]
```

`targetPose` 是 16 个关节值的数组（顺序：FR hip/thigh/calf, FL, RR, RL, 4x foot）。

---

## 环境变量

### 真机 (`han_dog.dart`)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HAN_DOG_PORT` | `13145` | gRPC 端口 |
| `HAN_DOG_IMU_PORT` | `/dev/ttyUSB1` | IMU 串口 |
| `HAN_DOG_YUNZHUO_PORT` | `/dev/yunzhuo` | 遥控器串口 |
| `HAN_DOG_MODEL` | `model/policy_260106.onnx` | ONNX 模型路径 |
| `HAN_DOG_ARBITER_TIMEOUT` | `3` | 仲裁器超时（秒） |
| `HAN_DOG_SENSOR_LOW_THRESHOLD` | `3` | 传感器低频告警阈值 |
| `HAN_DOG_SHUTDOWN_TIMEOUT` | `8` | 关机超时（秒） |
| `HAN_DOG_DEBUG_TUI` | `false` | 启用调试 TUI |
| `HAN_DOG_LOG` | `INFO` | 日志级别 |

### 仿真 (`server.dart`)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MEDULLA_PORT` | `13145` | gRPC 端口 |
| `MEDULLA_MODEL` | `model/policy.onnx` | ONNX 模型路径 |
| `MEDULLA_HISTORY_SIZE` | `1` | 历史缓冲区大小 |
| `MEDULLA_STANDUP_COUNTS` | `150` | 站起插值帧数 |
| `MEDULLA_SITDOWN_COUNTS` | `150` | 坐下插值帧数 |
| `MEDULLA_LOG` | `INFO` | 日志级别 |

---

## 测试

```bash
dart test han_dog_brain/        # 42 个：FSM 全路径 + Memory + Behaviour + Gesture
dart test han_dog/              # 71 个：ControlArbiter + RealControlDog + ProtoConvert + SimSensor
dart test frequency_watch/      # 8 个：频率统计
dart test skinny_dog_algebra/   # 10 个：JointsMatrix + clamp + NaN 检测
```

---

## 关键接口

推理核心通过接口与硬件解耦，方便替换实现：

```dart
abstract interface class ImuService {
  Vector3 get gyroscope;
  Vector3 get projectedGravity;
}

abstract interface class JointService {
  JointsMatrix get position;
  JointsMatrix get velocity;
}

abstract interface class MotorService {
  Future<void> enable();
  Future<void> disable();
}

abstract interface class SimStateInjector {
  Quaternion get quaternion;
  void injectSim({...});
}
```

| 接口 | 真机实现 | 仿真实现 |
|------|---------|---------|
| `ImuService` | `RealImu` | `SimSensorService` |
| `JointService` | `RealJoint` | `SimSensorService` |
| `SimStateInjector` | 不需要 | `SimSensorService` |
