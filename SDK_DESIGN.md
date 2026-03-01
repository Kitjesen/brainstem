# brainstem SDK 架构设计

> 版本: 1.0-draft | 日期: 2026-02-26

## 1. 目标

将 brainstem 的四足机器人控制能力封装为 SDK，支持三种集成方式：

1. **Dart 包依赖** -- 直接 import 使用 Brain/FSM/Behaviour
2. **gRPC 远程服务** -- 通过网络调用 CMS 服务
3. **配置注入** -- 通过接口和参数定制行为

---

## 2. 现状分析

### 2.1 当前包依赖关系

```
                  ┌─────────────────┐
                  │   han_dog (app)  │  真实硬件主程序
                  └──┬───┬───┬───┬──┘
                     │   │   │   │
        ┌────────────┘   │   │   └────────────────┐
        v                v   v                    v
  ┌───────────┐  ┌──────────────┐  ┌──────────────────┐
  │ frequency │  │ han_dog_brain│  │ han_dog_message   │
  │ _watch    │  │ (推理核心)   │  │ (Protobuf/gRPC)   │
  └───────────┘  └──┬──────┬───┘  └──────────────────┘
                    │      │              ^
                    v      v              │
           ┌────────┐  ┌──────────┐      │
           │onnx_   │  │skinny_dog│      │
           │runtime  │  │_algebra  │      │
           └────────┘  └──────────┘      │
                                         │
              han_dog_brain ─────────────┘
                (grpc + proto 依赖)
```

### 2.2 当前公开 API 表面

| 包 | barrel export | 导出内容 |
|----|---------------|----------|
| `han_dog_brain` | `han_dog_brain.dart` | `Brain`, `M` (FSM), `S`/`A` (状态/动作), `ImuService`, `JointService`, `MotorService`, `SimStateInjector`, `History`, `Command`, `Memory` |
| `han_dog` | `han_dog.dart` | `ControlArbiter`, `SimDogServer`, `SimImu`, `SimJoint`, `RealImu`, `RealJoint`, `RealDogServer`, `RealController`, `RealControlDog` |
| `han_dog_message` | `han_dog_message.dart` | 所有 proto 生成类: `CmsServiceBase`, `MujocoClient`, `History`, `Imu`, `Joint`, `SimState`, `Params`, `RobotModel`, `Command` 等 |
| `skinny_dog_algebra` | `skinny_dog_algebra.dart` | `JointsMatrix`, `JointsView`, `H` |

### 2.3 三个 gRPC 服务器的对比

| | `CmsServer` | `SimDogServer` | `RealDogServer` |
|--|-------------|----------------|-----------------|
| **位置** | `han_dog_brain/src/server/` | `han_dog/src/` | `han_dog/src/` |
| **用途** | 纯仿真 (MuJoCo) | 硬件+仿真混用 | 纯真实硬件 |
| **ControlArbiter** | 无 | 无 (直接操作 M) | 有 |
| **Tick 实现** | 调用 `brain.tick()` | 调用 `brain.memory.next` + `clock.add` | 返回空 History (no-op) |
| **Step 实现** | 通过 `SimStateInjector` 注入 | 直接写 `SimImu`/`SimJoint` | No-op |
| **kp/kd** | 不管理 | 按指令切换 kp/kd | 通过 `RealControlDog` 监听切换 |
| **listenHistory** | 通过 `proto_convert` 转换 | 手动构建 proto | 手动构建 proto (广播流) |
| **listenImu** | 读 `ImuService` + 时钟驱动 | 读 `_simStateController` | 读 `RealImu.stateStream` |
| **listenJoint** | 读 `JointService` + 时钟驱动 | 读 `_simStateController` | 读 `RealJoint.reportStream` |

**关键问题:**
- 三个服务器有大量重复的 proto 转换代码
- `SimDogServer` 和 `RealDogServer` 在 `han_dog` 包中，但实现的是同一个 `CmsServiceBase`
- `CmsServer` 已经最干净，但缺少 kp/kd 管理和 ControlArbiter 支持

### 2.4 接口抽象现状

```dart
// 已有的接口 (han_dog_brain/src/sensor.dart)
abstract interface class ImuService     // 陀螺仪 + 重力投影
abstract interface class JointService   // 关节位置 + 速度
abstract interface class MotorService   // enable/disable
abstract interface class SimStateInjector // 仿真数据注入
```

这些接口设计良好，是 SDK 化的基础。`Brain` 已经通过构造函数注入 `ImuService` 和 `JointService`，不直接依赖硬件。

---

## 3. SDK 分层架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Application Layer                              │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │ han_dog (真机)   │  │ medulla (仿真)    │  │ 第三方集成 App      │  │
│  └───────┬─────────┘  └────────┬─────────┘  └──────────┬───────────┘  │
│          │                     │                       │              │
│  ┌───────┴─────────────────────┴───────────────────────┴───────────┐  │
│  │                    Server SDK (han_dog_server)                   │  │  Layer C
│  │  UnifiedCmsServer + GainManager + ControlArbiter + HealthCheck  │  │
│  └───────┬─────────────────────┬───────────────────────┬───────────┘  │
│          │                     │                       │              │
│  ┌───────┴─────────────────────┴───────────────────────┴───────────┐  │
│  │                    Core SDK (han_dog_brain)                      │  │  Layer B
│  │  Brain + M(FSM) + Behaviour + Memory + sensor interfaces        │  │
│  └───────┬─────────────────────┬───────────────────────────────────┘  │
│          │                     │                                      │
│  ┌───────┴──────────┐  ┌──────┴──────────┐                           │
│  │ skinny_dog_algebra│  │  onnx_runtime   │                           │  Layer A
│  │ (数学库)          │  │  (FFI 绑定)     │                           │
│  └──────────────────┘  └─────────────────┘                           │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────────┐│
│  │              Hardware Adapters (han_dog)                          ││  Adapters
│  │  RealImu + RealJoint + RealController + RealControlDog           ││
│  └───────────────────────────────────────────────────────────────────┘│
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────────┐│
│  │              Protocol (han_dog_message)                           ││  Protocol
│  │  Proto 定义 + gRPC 生成代码                                       ││
│  └───────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Layer A -- Foundation (不变)

| 包 | 职责 | 变更 |
|----|------|------|
| `skinny_dog_algebra` | `JointsMatrix`, 向量扩展 | 无 |
| `onnx_runtime` | ONNX FFI 绑定 | 无 |
| `frequency_watch` | 频率监控 | 无 |

### 3.2 Layer B -- Core SDK (han_dog_brain, 小幅重构)

**目标:** 纯逻辑核心，零硬件/网络依赖。

当前 `han_dog_brain` 已经接近这个目标，仅需：

1. **将 `src/server/` 目录移出** -- `CmsServer`, `proto_convert`, `sim_sensor` 都依赖 `grpc` 和 `han_dog_message`，应移到 Server SDK 层
2. **保留核心导出:** `Brain`, `M`, `S`, `A`, `History`, `Command`, `Memory`, `ImuService`, `JointService`, `MotorService`, `SimStateInjector`, `Behaviour` (Idle/StandUp/SitDown/Walk)
3. **新增 `GainProvider` 接口** (可选)，让 Core 知道该用什么 kp/kd，但不强制

重构后的 `han_dog_brain` 依赖:
```yaml
dependencies:
  vector_math: ^2.2.0
  skinny_dog_algebra: ^1.0.0
  onnx_runtime: ^0.3.1
  cms: ^1.4.3
  freezed_annotation: ^3.1.0
  rxdart: ^0.28.0
  logging: ^1.3.0
  # 移除: grpc, han_dog_message
```

### 3.3 Layer C -- Server SDK (新包或 han_dog 内 server/ 模块)

**方案 A (推荐): 在 han_dog 包内重构**

将三个服务器合并为 `UnifiedCmsServer`，放在 `han_dog/lib/src/server/` 下。理由：
- 避免新增包带来的管理成本
- `han_dog` 已经同时依赖 `han_dog_brain` 和 `han_dog_message`
- Server 需要了解硬件适配器类型

**方案 B: 新建 `han_dog_server` 包**

如果未来有多个 app 需要复用 server 逻辑，可提取为独立包。

#### 3.3.1 UnifiedCmsServer 设计

将 `CmsServer` + `SimDogServer` + `RealDogServer` 合并为一个可配置的服务:

```dart
/// 运行模式
enum CmsMode {
  /// 纯仿真: Tick/Step 由外部驱动，无 ControlArbiter
  simulation,
  /// 真实硬件: 50Hz Timer 驱动，有 ControlArbiter
  hardware,
  /// 混合: 硬件传感器 + 仿真 Tick/Step (sim-to-real 验证)
  hybrid,
}

/// 增益管理器: 不同状态使用不同的 PD 增益
class GainManager {
  final JointsMatrix inferKp, inferKd;
  final JointsMatrix standUpKp, standUpKd;
  final JointsMatrix sitDownKp, sitDownKd;

  /// 根据 FSM 状态返回当前增益
  (JointsMatrix kp, JointsMatrix kd) gainsFor(S state);
}

/// 统一 CMS gRPC 服务
class UnifiedCmsServer extends CmsServiceBase {
  final Brain brain;
  final M m;
  final CmsMode mode;
  final ControlArbiter? arbiter;    // hardware/hybrid 模式需要
  final SimStateInjector? injector; // simulation/hybrid 模式需要
  final MotorService? motor;        // hardware 模式需要
  final GainManager? gains;         // 增益管理 (可选)

  // 传感器数据源 (用于 listenImu/listenJoint)
  final Stream<proto.Imu> Function()? imuStreamFactory;
  final Stream<proto.Joint> Function()? jointStreamFactory;

  UnifiedCmsServer({
    required this.brain,
    required this.m,
    this.mode = CmsMode.simulation,
    this.arbiter,
    this.injector,
    this.motor,
    this.gains,
    this.imuStreamFactory,
    this.jointStreamFactory,
  });

  // 运动指令: 根据 mode 决定是否经仲裁
  @override
  Future<Empty> walk(ServiceCall call, Vector3 request) async {
    final action = A.walk(request.toVM());
    if (arbiter != null) {
      if (!arbiter!.command(action, ControlSource.grpc)) {
        throw GrpcError.failedPrecondition('Control rejected');
      }
    } else {
      m.add(action);
    }
    return Empty();
  }

  // Tick: simulation/hybrid 可用，hardware 返回错误
  @override
  Future<proto.History> tick(ServiceCall call, Empty request) async {
    if (mode == CmsMode.hardware) {
      throw GrpcError.unimplemented('Tick not available in hardware mode');
    }
    return (await brain.tick()).toProto(timestamp: _elapsed());
  }

  // Step: 仅 simulation/hybrid 可用
  @override
  Future<Empty> step(ServiceCall call, SimState request) async {
    final inj = injector;
    if (inj == null) {
      throw GrpcError.failedPrecondition('Step requires simulation mode');
    }
    request.injectInto(inj);
    return Empty();
  }

  // 共用的 proto 转换逻辑 (消除重复代码)
  // ...
}
```

#### 3.3.2 对比: 三合一 vs 当前三个独立服务器

| 特性 | 当前 (3个) | 合并后 (1个) |
|------|-----------|-------------|
| proto 转换代码 | 3份几乎相同 | 1份，共用 `proto_convert.dart` |
| kp/kd 管理 | 分散在 SimDogServer + RealControlDog | 集中到 `GainManager` |
| ControlArbiter | 仅 RealDogServer | 可选注入 |
| listenHistory | 3种不同实现 | 1种，通过 `brain.historyStream` |
| listenImu/Joint | 3种不同数据源 | 通过 stream factory 注入 |
| 新增 RPC | 需改3处 | 改1处 |

### 3.4 Hardware Adapters (han_dog, 保持独立)

硬件驱动保持在 `han_dog` 包中，通过接口与 Core SDK 集成:

```
RealImu        implements  ImuService
RealJoint      implements  JointService  (+ enable/disable/realActionExt)
SimImu         implements  ImuService
SimJoint       implements  JointService
SimSensorService implements ImuService + JointService + SimStateInjector
```

`RealController` 和 `RealControlDog` 保持不变，是硬件层独有的。

---

## 4. Proto 修改建议

### 4.1 新增 GetModelInfo RPC

```protobuf
// 在 service Cms 中添加:
rpc GetModelInfo(google.protobuf.Empty) returns (ModelInfo);

// 新增消息:
message ModelInfo {
  // ONNX 模型是否已加载
  bool model_loaded = 1;
  // 模型文件路径 (仅供调试)
  string model_path = 2;
  // observation 维度 (historySize * 57)
  int32 observation_dim = 3;
  // 最近一次推理耗时 (微秒)
  int64 last_inference_us = 4;
}
```

### 4.2 新增 API 版本字段

```protobuf
// 在 Params 消息中添加:
message Params {
  RobotModel robot = 1;
  // API 版本号，客户端可据此做兼容性检查
  string api_version = 2;
  // 服务器运行模式
  CmsMode mode = 3;
}

enum CmsMode {
  SIMULATION = 0;
  HARDWARE = 1;
  HYBRID = 2;
}
```

### 4.3 gRPC Health Check

使用标准的 [gRPC Health Checking Protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md):

```protobuf
// 标准 health.proto (grpc_health_v1)
// Dart grpc 包自带支持，只需注册 HealthService
```

在 Dart 代码中:
```dart
// 使用 grpc 包内置的健康检查
import 'package:grpc/grpc.dart';

final healthService = HealthService();
healthService.setStatus('han_dog.Cms', ServingStatus.SERVING);

final server = Server.create(
  services: [cmsServer, healthService],
);
```

### 4.4 GetFsmState RPC

```protobuf
// 在 service Cms 中添加:
rpc GetFsmState(google.protobuf.Empty) returns (FsmState);
rpc ListenFsmState(google.protobuf.Empty) returns (stream FsmState);

message FsmState {
  enum State {
    ZERO = 0;
    GROUNDED = 1;
    STANDING = 2;
    WALKING = 3;
    TRANSITIONING_STAND_UP = 4;
    TRANSITIONING_SIT_DOWN = 5;
  }
  State state = 1;
  // 仲裁器当前控制源 (仅 hardware 模式有意义)
  string control_owner = 2;
}
```

---

## 5. 重构后的包依赖方向

```
han_dog_message          <-- 零依赖 (仅 protobuf + grpc)
    ^
    |
skinny_dog_algebra       <-- 仅 vector_math, equatable
    ^
    |
onnx_runtime             <-- 仅 ffi
    ^
    |
han_dog_brain            <-- skinny_dog_algebra + onnx_runtime + cms + rxdart
    ^                        不再依赖 grpc 和 han_dog_message
    |
han_dog                  <-- han_dog_brain + han_dog_message + robo_device
                             包含: UnifiedCmsServer + Hardware Adapters
                             包含: proto_convert (从 han_dog_brain 移入)
                             包含: SimSensorService (从 han_dog_brain 移入)
```

**关键变化:** `han_dog_brain` 不再依赖 `grpc` 和 `han_dog_message`，变成纯逻辑包。

---

## 6. 公开 API 设计

### 6.1 Core SDK (han_dog_brain)

```dart
// han_dog_brain.dart -- barrel export
export 'src/brain.dart';         // Brain (facade)
export 'src/cms/cms.dart';       // M (FSM), S (states), A (actions)
export 'src/sensor.dart';        // ImuService, JointService, MotorService, SimStateInjector
export 'src/common.dart';        // History, Command
export 'src/memory.dart';        // Memory<T>
export 'src/behaviour.dart';     // Behaviour, Idle, StandUp, SitDown, Walk, WalkObservation
```

使用方式:
```dart
import 'package:han_dog_brain/han_dog_brain.dart';

// 1. 实现传感器接口
class MyImu implements ImuService { ... }
class MyJoint implements JointService { ... }

// 2. 创建 Brain
final brain = Brain(
  imu: myImu,
  joint: myJoint,
  clock: myClock,
  standingPose: myStandingPose,
  sittingPose: mySittingPose,
);

// 3. 加载模型并使用
await brain.loadModel('model/policy.onnx');
final m = M(brain);
m.add(const A.init());
```

### 6.2 Server SDK (han_dog 内的 server 模块)

```dart
// han_dog.dart -- barrel export (新增)
// ... 现有 exports ...
export 'src/server/unified_cms_server.dart';  // UnifiedCmsServer
export 'src/server/gain_manager.dart';        // GainManager
export 'src/server/proto_convert.dart';       // proto 转换工具
export 'src/server/sim_sensor.dart';          // SimSensorService
```

使用方式 (仿真):
```dart
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';

final sim = SimSensorService(standingPose: pose);
final brain = Brain(imu: sim, joint: sim, clock: clock, ...);
final m = M(brain);

final server = grpc.Server.create(services: [
  UnifiedCmsServer(
    brain: brain,
    m: m,
    mode: CmsMode.simulation,
    injector: sim,
  ),
]);
```

使用方式 (真实硬件):
```dart
final imu = RealImu('/dev/ttyUSB1');
final joint = RealJoint(fr: .usbbus2, fl: .usbbus4, ...);
final brain = Brain(imu: imu, joint: joint, clock: clock, ...);
final m = M(brain);
final arbiter = ControlArbiter(m);

final server = grpc.Server.create(services: [
  UnifiedCmsServer(
    brain: brain,
    m: m,
    mode: CmsMode.hardware,
    arbiter: arbiter,
    motor: joint,  // RealJoint 也实现 enable/disable
    gains: GainManager(inferKp: ..., inferKd: ..., ...),
    imuStreamFactory: () => imu.stateStream.map(toProtoImu),
    jointStreamFactory: () => joint.reportStream.map(toProtoJoint),
  ),
]);
```

---

## 7. 合并服务器的具体方案

### 7.1 步骤

1. **创建 `han_dog/lib/src/server/` 目录**
2. **移动文件:**
   - `han_dog_brain/lib/src/server/proto_convert.dart` -> `han_dog/lib/src/server/proto_convert.dart`
   - `han_dog_brain/lib/src/server/sim_sensor.dart` -> `han_dog/lib/src/server/sim_sensor.dart`
   - `han_dog_brain/lib/src/server/cms_server.dart` -> 作为 `UnifiedCmsServer` 的基础
3. **创建 `unified_cms_server.dart`:**
   - 以 `CmsServer` 为基础 (最干净)
   - 添加 `CmsMode` 枚举
   - 添加可选 `ControlArbiter` (从 `RealDogServer` 合并)
   - 添加可选 `GainManager` (从 `SimDogServer` 提取)
   - 添加 stream factory 参数 (统一 listen 数据源)
   - 实现新 RPC: `GetModelInfo`, `GetFsmState`, `ListenFsmState`
4. **创建 `gain_manager.dart`:**
   - 提取 kp/kd 切换逻辑
   - 监听 FSM 状态自动切换
5. **更新 barrel exports**
6. **删除旧文件:** `sim_dog.dart`, `real_dog.dart` (功能已合并)
7. **更新 `han_dog_brain` 的 pubspec.yaml:** 移除 `grpc` 和 `han_dog_message` 依赖
8. **更新入口文件:** `han_dog/bin/han_dog.dart` 和 `han_dog_brain/bin/server.dart` 使用新的 `UnifiedCmsServer`

### 7.2 proto 转换代码统一

当前问题: `RealDogServer` 和 `SimDogServer` 各自手动构建 proto 对象，与 `CmsServer` 使用的 `proto_convert.dart` 不一致。

解决方案: 所有 proto 转换集中到 `proto_convert.dart`:

```dart
// proto_convert.dart 新增:

/// History -> proto.History (统一转换，含 kp/kd)
extension HistoryToProto on History {
  proto.History toProto({
    proto.Duration? timestamp,
    JointsMatrix? kp,
    JointsMatrix? kd,
  }) => proto.History(
    gyroscope: gyroscope.toProto(),
    projectedGravity: projectedGravity.toProto(),
    command: command.toProto(),
    jointPosition: jointPosition.toProto(),
    jointVelocity: jointVelocity.toProto(),
    action: action.toProto(),
    nextAction: nextAction.toProto(),
    timestamp: timestamp,
    kp: kp?.toProto(),
    kd: kd?.toProto(),
  );
}
```

### 7.3 listenImu / listenJoint 统一

当前每个服务器的 listen 实现差异很大:
- `CmsServer`: 时钟驱动，读 ImuService
- `SimDogServer`: `_simStateController` 流
- `RealDogServer`: `RealImu.stateStream` / `RealJoint.reportStream`

统一方案: 通过 stream factory 注入:

```dart
// UnifiedCmsServer 构造
UnifiedCmsServer({
  // ... 其他参数
  /// 自定义 IMU 流。未提供时使用默认的时钟驱动方式。
  Stream<proto.Imu> Function()? imuStreamFactory,
  /// 自定义 Joint 流。未提供时使用默认的时钟驱动方式。
  Stream<proto.Joint> Function()? jointStreamFactory,
});

@override
Stream<proto.Imu> listenImu(ServiceCall call, Empty request) {
  if (imuStreamFactory != null) return imuStreamFactory!();
  // 默认: 时钟驱动 (与当前 CmsServer 行为一致)
  return brain.ts.map((_) => imuSnapshot(brain.imu, ...));
}
```

---

## 8. 迁移路径

分步执行，每步保持所有测试通过。

### Phase 1: 提取 server 代码 (不改行为)

**目标:** 将 `han_dog_brain/src/server/` 移到 `han_dog/`，`han_dog_brain` 移除 gRPC 依赖。

1. 将 `proto_convert.dart`, `sim_sensor.dart`, `cms_server.dart` 复制到 `han_dog/lib/src/server/`
2. 更新 import 路径
3. 更新 `han_dog/lib/han_dog.dart` barrel export
4. 更新 `han_dog_brain/bin/server.dart` 的 import 改为从 `han_dog` 导入
5. 从 `han_dog_brain/pubspec.yaml` 移除 `grpc` 和 `han_dog_message`
6. 从 `han_dog_brain/lib/han_dog_brain.dart` 移除 server 相关 export
7. 运行 `dart analyze` 和 `dart test han_dog_brain/` 确认

**风险:** 低。仅移动文件 + 更新 import。

### Phase 2: 合并三个服务器

**目标:** 创建 `UnifiedCmsServer` 替换三个独立服务器。

1. 创建 `han_dog/lib/src/server/unified_cms_server.dart`
2. 以 `CmsServer` 为基础添加 `CmsMode` / `ControlArbiter` / `GainManager`
3. 创建 `han_dog/lib/src/server/gain_manager.dart`
4. 统一 proto 转换: 扩展 `proto_convert.dart`
5. 更新 `han_dog/bin/han_dog.dart` 使用 `UnifiedCmsServer`
6. 更新 `han_dog_brain/bin/server.dart` 使用 `UnifiedCmsServer`
7. 验证: 仿真模式 + 真机模式都正常工作
8. 删除旧服务器: `sim_dog.dart`, `real_dog.dart`, 旧 `cms_server.dart`

**风险:** 中。需要仔细验证三种模式下的行为等价性。

### Phase 3: Proto 增强

**目标:** 添加新 RPC 和字段。

1. 编辑 `cms.proto`: 添加 `GetModelInfo`, `GetFsmState`, `ListenFsmState`, `Params.api_version`, `CmsMode`
2. 运行 `protoc` 重新生成
3. 在 `UnifiedCmsServer` 中实现新 RPC
4. 添加 gRPC Health Check service

**风险:** 低。纯增量添加，不破坏现有客户端。

### Phase 4: 文档和示例

1. 更新 `CLAUDE.md` 反映新架构
2. 在 `han_dog_brain/example/` 添加纯 Dart 集成示例
3. 在 `han_dog/example/` 添加 gRPC 集成示例

---

## 9. 不在本次范围

以下功能留作后续迭代:

- **Proto breaking changes** -- 现有字段编号不变，只做增量
- **dart pub publish** -- 当前 `publish_to: none`，SDK 暂不公开发布
- **WebSocket/REST 网关** -- 如需浏览器访问，后续添加 grpc-web 代理
- **多机器人实例** -- 当前架构面向单机器人，多实例需要状态隔离重构

---

## 10. 总结

| 维度 | 当前状态 | SDK 化后 |
|------|---------|---------|
| Brain 核心 | 混合 gRPC 依赖 | 纯逻辑，零网络依赖 |
| gRPC 服务 | 3 个实现，大量重复 | 1 个 `UnifiedCmsServer`，模式可配 |
| proto 转换 | 3 套手动代码 | 1 套 `proto_convert.dart` |
| kp/kd 管理 | 分散在多处 | 集中到 `GainManager` |
| 集成方式 | 复制代码 | Dart 包依赖 / gRPC 远程调用 |
| 健康检查 | 无 | 标准 gRPC Health Check |
| 模型信息 | 无 RPC | `GetModelInfo` RPC |
| FSM 可观测性 | 无 RPC | `GetFsmState` + `ListenFsmState` |
