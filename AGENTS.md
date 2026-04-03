# brainstem — Cursor Agent 工作指南

> 四足机器人控制系统。基于 ONNX 强化学习推理，支持真实硬件和 MuJoCo 仿真两种运行模式。
> 完整项目文档见 [README.md](README.md)，高层架构设计见 [SDK_DESIGN.md](SDK_DESIGN.md)。

## 常用命令

```bash
flutter pub get                        # 获取依赖（workspace 含 Flutter，必须用 flutter pub get）
dart analyze han_dog_brain/ han_dog/   # 必须零 issue（strict 模式已开启）
dart test han_dog_brain/ han_dog/ frequency_watch/ skinny_dog_algebra/  # 232+ 个测试全部通过
```

**原则：** 每次修改后，必须 `dart analyze` 零 issue + 所有测试通过。

### Freezed / build_runner

```bash
cd han_dog_brain && dart run build_runner build --delete-conflicting-outputs
```

必须在包目录下运行。

## 不可编辑的生成文件

- `*.freezed.dart` — Freezed 生成，运行 build_runner 重新生成
- `*.g.dart` — JSON / build_runner 生成
- `*.pb.dart` / `*.pbgrpc.dart` / `*.pbenum.dart` — protoc 生成（在 `han_dog_message/` 中）

## Strict 模式

`han_dog_brain/` 和 `han_dog/` 已启用 `strict-casts` / `strict-raw-types` / `strict-inference`。所有新代码必须满足：

- `Future<void>.delayed(...)` 而非 `Future.delayed(...)`
- 容器泛型必须显式：`List<StreamSubscription<Object?>>` 而非裸 `List<StreamSubscription>`

## 架构速查（4-Tier, 12 packages）

### Tier 1 — 运控核心

| 包 | 说明 |
|----|------|
| `han_dog` | 主程序入口、UnifiedCmsServer、硬件驱动、ControlArbiter、Xbox/Gamepad |
| `han_dog_brain` | Brain、FSM、Behaviour、Memory、Gesture SDK（纯逻辑，无网络/硬件依赖）|
| `skinny_dog_algebra` | JointsMatrix（16 关节矩阵） |

### Tier 2 — 硬件驱动

| 包 | 说明 |
|----|------|
| `robo_device` | 机器人设备抽象层（依赖 pcan + serial_port + protoframe） |
| `pcan` | PCAN CAN 总线通信 FFI |
| `serial_port` | 串口通信 FFI |
| `onnx_runtime` | ONNX Runtime 推理 FFI 绑定 |

### Tier 3 — 协议层

| 包 | 说明 |
|----|------|
| `han_dog_message` | protoc 生成的 gRPC 消息，**不可手动编辑** |
| `robo_device_proto` | robo_device 的 protobuf 定义 |
| `protoframe` | 协议帧序列化/反序列化 |

### Tier 4 — 应用 / 工具

| 包 | 说明 |
|----|------|
| `sirius` | Flutter Desktop 控制台 UI（通过 gRPC 连接 han_dog） |
| `sim/` | MuJoCo 物理仿真资源（URDF/XML/STL/Python 脚本，非 Dart 包） |
| `frequency_watch` | 频率监控工具库 |

### 依赖图

```
                    han_dog (主程序)
                   /    |     \      \
        han_dog_brain  freq_watch  robo_device  han_dog_message
           /    \                   /   |   \
  skinny_dog  onnx_runtime     pcan serial protoframe
   _algebra                         _port
                                robo_device_proto
```

## 主程序入口

| 入口 | 路径 | 用途 |
|------|------|------|
| 真机 | `han_dog/bin/han_dog.dart` | 50Hz Timer 驱动，连接 IMU/PCAN/YUNZHUO |
| 仿真 | `han_dog/bin/server.dart` | MuJoCo 通过 gRPC tick/step 驱动 |

## 编码规范

### 日志

```dart
final _log = Logger('han_dog.server');   // 包名.模块名
_log.severe('描述', error, stackTrace);  // onError 必须带 StackTrace
```

### Stream

- `cancel()` 不触发 `onDone`（Dart 保证）
- 状态切换先 `await sub.cancel()` 再建新订阅
- 所有 `listen()` 必须提供 `onError`
- 所有 `firstWhere()` **必须加 `.timeout()`**，防止启动死锁

### HanDogConfig 关键超时

| 字段 | 环境变量 | 默认 | 用途 |
|------|----------|------|------|
| `startupTimeout` | `HAN_DOG_STARTUP_TIMEOUT` | 10s | FSM 等待 Grounded 超时 |
| `shutdownTimeout` | `HAN_DOG_SHUTDOWN_TIMEOUT` | 8s | 关机等待超时 |
| `arbiterTimeout` | `HAN_DOG_ARBITER_TIMEOUT` | 3s | 控制权释放超时 |

### gRPC 服务

`UnifiedCmsServer` 是唯一的 gRPC 实现，通过 `CmsMode` 切换：

- `simulation` — 无 ControlArbiter，有 SimStateInjector
- `hardware` — 有 ControlArbiter，无 SimStateInjector

### 电机输出

`han_dog.dart` 中电机输出通过 `motorOutputEnabled` 标志控制，由遥控器 Enable 按钮或 gRPC `Enable()` RPC 激活。

## FSM 状态转换

```
Zero ──Init──> Grounded ──StandUp──> Transitioning ──Done──> Standing
                   ^                                          │  ^
                   │ SitDown Done                       Walk  │  │ Gesture Done
                   │                                          v  │
              Transitioning(SitDown)                     Walking ─┘
```

## 术语表

| 术语 | 含义 |
|------|------|
| `han_dog.dart` | 真实硬件主程序入口（50Hz Timer 驱动） |
| `server.dart` / medulla | 仿真模式主程序入口（MuJoCo gRPC，Logger 名 `han_dog.medulla`） |
| UnifiedCmsServer | 统一 gRPC 服务，取代了旧的 RealDogServer / SimDogServer |
| SimSensorService | 仿真传感器（实现 ImuService + JointService + SimStateInjector） |
| RealControlDog | YUNZHUO 遥控器驱动，将摇杆信号转换为 FSM 动作 |
| Brain | 推理核心 facade（在 han_dog_brain 中），封装 ONNX 推理 + FSM 行为 |
| M / A / S | FSM 的机器 / 动作 / 状态（Cms<S,A>，在 han_dog_brain/cms/ 中）|
| ProfileManager | 策略切换编排器，汇集 Brain + GainManager + RealControlDog |
| ControlArbiter | gRPC 与 YUNZHUO 遥控器的控制权仲裁器（yunzhuo 优先级更高）|

## `_archive/` 目录

旧版代码/资源归档（untracked），不参与构建，不要修改。
