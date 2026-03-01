# brainstem — Claude 工作指南

> 完整项目文档见 [README.md](README.md)

## 常用命令

```bash
dart analyze                      # 必须零 error（唯一 warning 在 onnx_runtime 生成文件中）
dart test han_dog_brain/ han_dog/ frequency_watch/ skinny_dog_algebra/  # 131 个测试全部通过
dart pub get                      # 获取依赖
dart run build_runner build --delete-conflicting-outputs  # 重新生成 Freezed 代码
```

**原则：** 每次修改后，必须 `dart analyze` 零 error + 131 个测试全部通过。

**build_runner 注意：** 必须在包目录下运行（如 `cd han_dog_brain && dart run build_runner build --delete-conflicting-outputs`）。

## 架构速查

| 层 | 包 | 说明 |
|----|----|----|
| 硬件 + gRPC | `han_dog` | 主程序入口、UnifiedCmsServer、硬件驱动、ControlArbiter |
| 推理核心 | `han_dog_brain` | Brain、FSM、Behaviour、Memory、**Gesture SDK**（**纯逻辑，无网络/硬件依赖**）|
| 数学 | `skinny_dog_algebra` | JointsMatrix（16 关节矩阵） |
| 协议 | `han_dog_message` | protoc 生成，**不可手动编辑** |

## 主程序入口

| 入口 | 路径 | 用途 |
|------|------|------|
| 真机 | `han_dog/bin/han_dog.dart` | 50Hz Timer 驱动，连接 IMU/PCAN/YUNZHUO |
| 仿真 | `han_dog/bin/server.dart` | MuJoCo 通过 gRPC tick/step 驱动 |

## 不可编辑的生成文件

- `*.freezed.dart` — Freezed，运行 build_runner 重新生成
- `*.g.dart` — JSON / build_runner 生成
- `*.pb.dart` / `*.pbgrpc.dart` / `*.pbenum.dart` — protoc 生成

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

### gRPC 服务
`UnifiedCmsServer` 是唯一的 gRPC 实现，通过 `CmsMode` 切换：
- `simulation` — 无 ControlArbiter，有 SimStateInjector
- `hardware` — 有 ControlArbiter，无 SimStateInjector

### 电机输出
`han_dog.dart` 中电机输出当前已注释（`// joint.realActionExt(action)`），这是**有意为之**（测试阶段），不要取消注释。

## .claude/ 配置

hookify 规则：
- `block-generated-dart` — 阻止编辑 `.freezed.dart` / `.g.dart`
- `block-proto-generated` — 阻止编辑 protoc 生成的 `.pb.dart`
- `warn-dangerous-git` — 警告 force push / hard reset
- `require-analyze-before-stop` — 停止前提醒运行 analyze + test
