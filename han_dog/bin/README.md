# han_dog/bin — 可运行程序说明

## 生产入口

| 程序 | 命令 | 用途 |
|------|------|------|
| `han_dog.dart` | `dart run han_dog/bin/han_dog.dart` | 真实硬件主程序（50Hz Timer，连接 IMU/PCAN/YUNZHUO） |
| `server.dart` | `dart run han_dog/bin/server.dart` | 仿真服务器（MuJoCo 通过 gRPC Tick/Step 驱动） |

## 调试工具（非生产）

| 程序 | 命令 | 用途 |
|------|------|------|
| `ping.dart` | `dart run han_dog/bin/ping.dart` | 按腿逐电机 PCAN CAN ping（需要硬件） |
| `ping_raw.dart` | `dart run han_dog/bin/ping_raw.dart` | 原始 4 路 CAN 全扫描（canId 0~254） |
| `test_grpc.dart` | `dart run han_dog/bin/test_grpc.dart` | 本地 gRPC 全接口测试（连接 localhost:13145） |

## 环境变量

### han_dog.dart（真机）
| 变量 | 默认 | 说明 |
|------|------|------|
| `HAN_DOG_PORT` | 13145 | gRPC 监听端口 |
| `HAN_DOG_PROFILE_DIR` | `profiles` | 策略 JSON 目录 |
| `HAN_DOG_DEFAULT_PROFILE` | （第一个）| 默认策略名 |

### server.dart（仿真）
| 变量 | 默认 | 说明 |
|------|------|------|
| `MEDULLA_PORT` | 13145 | gRPC 监听端口 |
| `MEDULLA_PROFILE_DIR` | `profiles` | 策略 JSON 目录 |
| `MEDULLA_DEFAULT_PROFILE` | （第一个）| 默认策略名 |
| `MEDULLA_LOG` | `INFO` | 日志级别（FINE/INFO/WARNING/SEVERE） |
