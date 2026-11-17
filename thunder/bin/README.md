# thunder/bin — 可运行程序说明

## 生产入口

| 程序 | 命令 | 用途 |
|------|------|------|
| `thunder.dart` | `dart run thunder/bin/thunder.dart` | 真实硬件主程序（50Hz Timer，连接 IMU/PCAN/YUNZHUO） |
| `server.dart` | `dart run thunder/bin/server.dart` | 仿真服务器（MuJoCo 通过 gRPC Tick/Step 驱动） |

## 调试工具（非生产）

| 程序 | 命令 | 用途 |
|------|------|------|
| `ping.dart` | `dart run thunder/bin/ping.dart` | 按腿逐电机 PCAN CAN ping（需要硬件） |
| `ping_raw.dart` | `dart run thunder/bin/ping_raw.dart` | 原始 4 路 CAN 全扫描（canId 0~254） |
| `test_grpc.dart` | `dart run thunder/bin/test_grpc.dart` | 本地 gRPC 全接口测试（连接 localhost:13145） |

## 环境变量

### thunder.dart（真机）
| 变量 | 默认 | 说明 |
|------|------|------|
| `THUNDER_PORT` | 13145 | gRPC 监听端口 |
| `THUNDER_PROFILE_DIR` | `profiles` | 策略 JSON 目录 |
| `THUNDER_DEFAULT_PROFILE` | （第一个）| 默认策略名 |

### server.dart（仿真）
| 变量 | 默认 | 说明 |
|------|------|------|
| `MEDULLA_PORT` | 13145 | gRPC 监听端口 |
| `MEDULLA_PROFILE_DIR` | `profiles` | 策略 JSON 目录 |
| `MEDULLA_DEFAULT_PROFILE` | （第一个）| 默认策略名 |
| `MEDULLA_LOG` | `INFO` | 日志级别（FINE/INFO/WARNING/SEVERE） |
