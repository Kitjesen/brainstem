# han_dog_message

四足机器人 **Han Dog** 的 gRPC/Protobuf 消息定义包，提供 Dart 和 Python 双语言支持。

## 概述

本包定义了机器人控制系统的所有通信协议，包含以下 gRPC 服务：

| 服务 | 用途 | 定义文件 |
|------|------|---------|
| **Cms** | 主控服务：运动指令 + 传感器监控 | `cms.proto` |
| **Mujoco** | MuJoCo 物理仿真接口 | `mujoco.proto` |
| **MujocoViewer** | MuJoCo 可视化回放 | `mujoco.proto` |

## 关节索引约定

所有 `Matrix4` 消息存储 16 个关节值，顺序固定：

```
索引  关节
────────────────────
 0    FR_hip    (前右髋)
 1    FR_thigh  (前右大腿)
 2    FR_calf   (前右小腿)
 3    FL_hip    (前左髋)
 4    FL_thigh  (前左大腿)
 5    FL_calf   (前左小腿)
 6    RR_hip    (后右髋)
 7    RR_thigh  (后右大腿)
 8    RR_calf   (后右小腿)
 9    RL_hip    (后左髋)
10    RL_thigh  (后左大腿)
11    RL_calf   (后左小腿)
12    FR_foot   (前右脚踝)
13    FL_foot   (前左脚踝)
14    RR_foot   (后右脚踝)
15    RL_foot   (后左脚踝)
```

## 单位约定

| 物理量 | 单位 |
|--------|------|
| 关节角度 | rad |
| 关节角速度 | rad/s |
| IMU 角速度 | rad/s |
| 力矩 | N·m |
| 行走方向 | 归一化 [-1, 1] |
| 重力投影 | 单位向量 |
| 时间戳 | `google.protobuf.Duration`（相对于会话开始时间） |

## 坐标系

- **Body frame**：IMU 的角速度和重力投影均在机器人体坐标系下表示
- **重力投影**：静止水平放置时为 `(0, 0, -1)`
- **行走方向**：`x` = 前后（正=前），`y` = 左右（正=左），`z` = 旋转（正=逆时针）
- **四元数**：Hamilton 约定 `q = w + xi + yj + zk`，表示 world → body 旋转

## 项目结构

```
han_dog_message/
├── han_dog_message/        # Proto 源文件
│   ├── common.proto        #   通用数据类型（Vector3, Matrix4, Quaternion 等）
│   ├── cms.proto           #   主控服务（指令 + 监控）
│   └── mujoco.proto        #   MuJoCo 仿真接口
├── dart/                   # Dart 生成代码 + 包配置
│   ├── lib/
│   │   ├── han_dog_message.dart       # Barrel 导出
│   │   ├── han_dog_message/*.pb.dart  # 生成的消息类
│   │   └── google/protobuf/*.pb.dart  # Well-known types
│   └── example/
├── python/                 # Python 生成代码 + 包配置
│   ├── han_dog_message/*_pb2.py       # 生成的消息类
│   ├── google/protobuf/*_pb2.py       # Well-known types
│   └── example/
└── tool/
    └── publish.dart        # 版本发布脚本
```

> Proto 文件放在 `han_dog_message/` 而非 `protos/`，是为了兼容 Python 的包导入路径。

## 安装

### Dart

```yaml
# pubspec.yaml
dependencies:
  han_dog_message:
    git:
      url: https://github.com/Kitjesen/han_dog_message
      path: dart
      tag_pattern: v{{version}}
    version: ^5.0.3
```

### Python

```bash
pip install git+https://github.com/Kitjesen/han_dog_message.git#subdirectory=python
```

## 快速开始

### Dart 客户端

```dart
import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart';

final channel = ClientChannel('localhost', port: 13145);
final client = CmsClient(channel);

// 订阅实时推理数据
await for (final history in client.listenHistory(Empty())) {
  print('关节角度: ${history.jointPosition.values}');
  print('重力投影: ${history.projectedGravity}');
}
```

### Python 客户端

```python
import grpc
from han_dog_message import cms_pb2, cms_pb2_grpc
from google.protobuf.empty_pb2 import Empty

channel = grpc.insecure_channel('localhost:13145')
stub = cms_pb2_grpc.CmsStub(channel)

# 订阅实时推理数据
for history in stub.ListenHistory(Empty()):
    print(f'关节角度: {list(history.joint_position.values)}')
    print(f'重力投影: ({history.projected_gravity.x}, {history.projected_gravity.y}, {history.projected_gravity.z})')
```

## 重新生成代码

需要先安装 protobuf 编译器：

```bash
sudo apt-get install -y protobuf-compiler
protoc --version
```

### 生成 Dart 代码

```bash
# Well-known types（只需执行一次）
protoc --dart_out=dart/lib \
  --proto_path=/path/to/protoc/include \
  google/protobuf/empty.proto \
  google/protobuf/duration.proto \
  google/protobuf/timestamp.proto

# 项目 proto（含 gRPC）
protoc --dart_out=grpc:dart/lib/ -I . han_dog_message/*
```

### 生成 Python 代码

```bash
cd python
poetry run python -m grpc_tools.protoc \
  -I .. \
  --python_out=. --pyi_out=. --grpc_python_out=. \
  ../han_dog_message/*.proto
```

## 发布新版本

1. 重新生成 proto 代码（如果 `.proto` 有改动）
2. 同步更新 `dart/pubspec.yaml` 和 `python/pyproject.toml` 中的版本号
3. 运行发布脚本：

```bash
dart run tool/publish.dart
```
