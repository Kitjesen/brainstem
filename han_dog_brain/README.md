# han_dog_brain

推理核心库 -- Brain facade、FSM 状态机、行为层。

## 概述

`han_dog_brain` 是一个**纯逻辑库**，不包含任何硬件驱动或网络代码。它通过 `ImuService` / `JointService` 抽象接口接收传感器数据，由上层（`han_dog`）负责对接真实硬件或仿真传感器。

**不可直接运行**，主程序入口在 `han_dog/bin/` 中。

## Brain Facade

`Brain` 是推理核心的唯一入口，服务层只与 Brain 交互，不穿透到内部组件。

### 核心 API

```dart
class Brain {
  /// 16 关节站立目标位置
  JointsMatrix get standingPose;

  /// ONNX 模型是否已加载
  bool get isModelLoaded;

  /// 最近一次推理耗时（微秒），用于监控控制循环性能
  int get lastInferenceUs;

  /// 推理历史流：每产生一帧新 History 即推送
  Stream<History> get historyStream;

  /// 触发一次时钟脉冲，等待并返回该帧推理结果
  /// 默认 2 秒超时防止 ONNX 异常导致调用方永久挂起
  Future<History> tick({Duration timeout = const Duration(seconds: 2)});

  /// 加载 ONNX 模型
  Future<void> loadModel(String path, {String? inputName});

  /// 切换策略（必须在 FSM Grounded 状态下调用）
  /// 替换 Walk/StandUp/SitDown 行为并重新加载模型
  /// 模型加载失败时自动回滚，保证 Brain 始终可用
  Future<void> switchProfile({
    required JointsMatrix standingPose,
    required JointsMatrix sittingPose,
    required String modelPath,
    // ...其他参数
  });

  /// 根据名称从动作库创建 Gesture 行为（未找到返回 null）
  Gesture? createGesture(String name);

  void dispose();
}
```

## FSM 状态机

FSM 定义在 `lib/src/cms/` 中，使用 `Cms<S, A>` 泛型状态机（来自 `cms` 包）。

### 状态（S）

| 状态 | 说明 |
|------|------|
| `Zero` | 初始态，等待 Init |
| `Grounded` | 着地（Idle 行为运行中） |
| `Standing` | 站立完成（Idle 行为运行中） |
| `Walking` | 行走中（ONNX 推理驱动） |
| `Transitioning` | 过渡态（StandUp/SitDown/Gesture 执行中，可挂 pending 动作） |

### 动作（A）

| 动作 | 说明 |
|------|------|
| `Init` | 初始化 → Zero 进入 Grounded |
| `StandUp` | 站起 |
| `SitDown` | 坐下 |
| `Walk(direction)` | 开始行走 / 更新方向 |
| `Idle` | 回到站立（Walking 摇杆归零超时后使用） |
| `Gesture(name)` | 播放预定义动作 |
| `Fault(reason)` | 异常触发安全着陆 |
| `Done` | 过渡完成，由行为流关闭时自动触发 |

### 状态转换概览

```
Zero ──Init──→ Grounded
                  │
               StandUp
                  ↓
             Transitioning(StandUp)
                  │
                Done
                  ↓
              Standing ←──Idle/StandUp── Walking
                  │                        ↑
               SitDown                   Walk
                  ↓                        │
             Transitioning(SitDown)    Standing
                  │
                Done
                  ↓
              Grounded
```

## 内置行为

| 行为 | 文件 | 说明 |
|------|------|------|
| `Idle` | behaviour.dart | 着地/站立时的保持行为，输出当前关节位置 |
| `StandUp` | behaviour.dart | lerp 从坐姿到站姿，counts+1 帧 |
| `SitDown` | behaviour.dart | lerp 从站姿到坐姿，counts+1 帧 |
| `Walk` | behaviour.dart | ONNX 神经网络推理驱动行走 |
| `Gesture` | gesture.dart | 播放 GestureDefinition 预定义关节轨迹 |

## 接口规范

### ImuService

```dart
abstract interface class ImuService {
  Vector3 get gyroscope;
  Vector3 get projectedGravity;
  Vector3 get initialGyroscope;
  Vector3 get initialProjectedGravity;
}
```

### JointService

```dart
abstract interface class JointService {
  JointsMatrix get position;
  JointsMatrix get velocity;
  JointsMatrix get initialPosition;
  JointsMatrix get initialVelocity;
}
```

### SimStateInjector（仅仿真）

```dart
abstract interface class SimStateInjector {
  Quaternion get quaternion;
  void injectSim({
    required Vector3 gyroscope,
    required Quaternion quaternion,
    required JointsMatrix position,
    required JointsMatrix velocity,
    JointsMatrix? torque,
  });
}
```

> 真实硬件中 `quaternion` 和 `torque` 不可用。`ImuService` 不含 quaternion，`JointService` 不含 torque。

## 使用示例（仿真模式）

```dart
import 'package:han_dog_brain/han_dog_brain.dart';

// 创建时钟控制器
final clock = StreamController<void>();

// 创建仿真传感器（实现 ImuService + JointService + SimStateInjector）
final sensor = SimSensorService();

// 创建 Brain
final brain = Brain(
  imu: sensor,
  joint: sensor,
  clock: clock,
  standingPose: profile.standingPose,
  sittingPose: profile.sittingPose,
);

// 加载 ONNX 模型
await brain.loadModel(profile.modelPath);

// 推理一帧
final history = await brain.tick();
```

## 内部结构

```
han_dog_brain/lib/src/
├── brain.dart              # Brain facade
├── sensor.dart             # ImuService / JointService / SimStateInjector 接口
├── behaviour.dart          # Idle / StandUp / SitDown / Walk
├── gesture.dart            # Gesture 行为 + GestureLibrary
├── common.dart             # History / Command 数据类（Freezed）
├── memory.dart             # Memory 环形缓冲区
├── observation_builder.dart # ONNX 输入向量构造器
└── cms/
    ├── cms.dart            # FSM 状态机实现
    ├── a.dart              # 动作定义（Freezed sealed class）
    └── s.dart              # 状态定义（Freezed sealed class）
```
