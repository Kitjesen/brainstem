# han_dog

真实硬件运行时 -- 硬件驱动、gRPC 服务和应用层配置。

## 职责

`han_dog` 是机器狗的主程序包，负责：

- 驱动真实硬件（IMU 串口、PCAN 关节总线、YUNZHUO 遥控器）
- 提供 `UnifiedCmsServer` gRPC 服务（供桌面控制面板 sirius 和导航板 lingtu 远程调用）
- 通过 `ControlArbiter` 仲裁 gRPC 与 YUNZHUO 遥控器的控制权
- 管理策略（Profile）的加载、切换和热重载

## 与 han_dog_brain 的关系

`han_dog` 依赖 `han_dog_brain`。`han_dog_brain` 是纯推理核心库（Brain + FSM + Behaviour），不含任何硬件或网络代码。`han_dog` 负责将真实硬件传感器接入 Brain 的 `ImuService` / `JointService` 接口，并将 Brain 的推理输出写入电机。

## 内部结构

```
han_dog/
├── bin/
│   ├── han_dog.dart       # 真机主入口（50Hz Timer 驱动）
│   ├── server.dart        # 仿真主入口（MuJoCo gRPC 驱动，Logger: han_dog.medulla）
│   ├── ping.dart          # 调试：PCAN CAN 总线电机 ping
│   ├── ping_raw.dart      # 调试：原始 4 路 CAN 全扫描
│   └── test_grpc.dart     # 调试：本地 gRPC 接口测试
├── lib/
│   └── src/
│       ├── app/                        # 应用层（配置、监控、策略）
│       │   ├── config.dart             #   HanDogConfig（环境变量配置）
│       │   ├── monitoring.dart         #   传感器频率监控 + TUI 调试面板
│       │   ├── profile_manager.dart    #   策略切换编排器（Brain + GainManager + RealControlDog）
│       │   └── robot_profile.dart      #   RobotProfile JSON 策略定义
│       ├── server/                     # gRPC 服务层
│       │   ├── unified_cms_server.dart #   UnifiedCmsServer（唯一 gRPC 实现）
│       │   ├── gain_manager.dart       #   kp/kd 增益管理
│       │   ├── sim_sensor.dart         #   SimSensorService（仿真传感器）
│       │   └── proto_convert.dart      #   Protobuf 类型转换工具
│       ├── real_imu.dart               # IMU 串口驱动
│       ├── real_joint.dart             # PCAN 关节总线驱动
│       ├── real_controller.dart        # YUNZHUO 串口驱动
│       ├── real_control_dog.dart       # 遥控器摇杆 → FSM 动作桥接
│       ├── control_arbiter.dart        # 控制权仲裁器（yunzhuo 优先级更高）
│       ├── sim_imu.dart                # [已废弃] 使用 SimSensorService 替代
│       └── sim_joint.dart              # [已废弃] 使用 SimSensorService 替代
├── profiles/
│   ├── mini.json           # 参考策略文件
│   └── default.json        # 默认策略文件
└── test/
```

## 主程序入口

### han_dog.dart（真机）

50Hz `Timer.periodic` 驱动时钟，连接 IMU/PCAN/YUNZHUO 硬件。启动流程：

1. 读取 `HanDogConfig` 环境变量配置
2. 加载 `profiles/` 目录中的策略文件
3. 初始化硬件驱动（RealImu、RealJoint、RealController）
4. 创建 Brain 并加载 ONNX 模型
5. 启动 UnifiedCmsServer gRPC 服务
6. 进入 50Hz 控制循环

```bash
dart run han_dog/bin/han_dog.dart
```

### server.dart（仿真 / medulla）

MuJoCo 仿真模式。无硬件依赖，通过 gRPC `tick`/`step` 由 MuJoCo Python 端驱动时钟。

```bash
dart run han_dog/bin/server.dart
```

## 环境变量

### han_dog.dart 使用

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HAN_DOG_PORT` | `13145` | gRPC 服务端口 |
| `HAN_DOG_PROFILE_DIR` | `profiles` | 策略 JSON 文件目录 |
| `HAN_DOG_DEFAULT_PROFILE` | _(第一个)_ | 默认策略名称 |
| `HAN_DOG_IMU_PORT` | `/dev/ttyUSB1` | IMU 串口路径 |
| `HAN_DOG_YUNZHUO_PORT` | `/dev/yunzhuo` | YUNZHUO 遥控器串口路径 |
| `HAN_DOG_ARBITER_TIMEOUT` | `3` (秒) | 控制权释放超时 |
| `HAN_DOG_STARTUP_TIMEOUT` | `10` (秒) | FSM 等待 Grounded 超时 |
| `HAN_DOG_SHUTDOWN_TIMEOUT` | `8` (秒) | 关机等待超时 |
| `HAN_DOG_JOINT_LIMIT_RAD` | `3.14` | 关节安全限位（rad） |
| `HAN_DOG_SENSOR_LOW_THRESHOLD` | `3` | 传感器降频容忍次数 |
| `HAN_DOG_LOG_DIR` | `logs` | 日志目录（空字符串禁用） |
| `HAN_DOG_DEBUG_TUI` | `false` | 启用 ANSI 调试 TUI |

### server.dart 使用

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MEDULLA_PORT` | `13145` | gRPC 服务端口 |
| `MEDULLA_PROFILE_DIR` | `profiles` | 策略 JSON 文件目录 |
| `MEDULLA_DEFAULT_PROFILE` | _(第一个)_ | 默认策略名称 |
| `MEDULLA_HISTORY_SIZE` | `1` | 观测历史帧数 |

## 策略文件（profiles/）

策略文件为 JSON 格式，定义机器人的运动参数。参考 `profiles/mini.json`：

- `name` -- 策略唯一标识
- `description` -- 策略描述
- `modelPath` -- ONNX 模型文件路径
- `standingPose` / `sittingPose` -- 16 关节目标位置
- `kp` / `kd` -- 16 关节 PD 控制增益

至少需要一个策略文件才能启动。

## 调试工具

这些脚本仅用于开发调试，不在生产环境中使用：

```bash
dart run han_dog/bin/ping.dart        # PCAN CAN 总线电机 ping
dart run han_dog/bin/ping_raw.dart    # 原始 4 路 CAN 全扫描
dart run han_dog/bin/test_grpc.dart   # 本地 gRPC 接口测试
```
