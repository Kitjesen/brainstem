# sirius

Flutter Windows 桌面控制面板 -- 通过 gRPC 远程监控和控制机器狗。

## 概述

sirius 是机器狗的桌面控制面板应用，基于 Flutter Desktop（Windows）构建。通过 gRPC 连接 `han_dog` 的 `UnifiedCmsServer`，实现实时状态监控、远程控制和参数调整。

## 运行

```bash
# 开发模式运行
cd sirius
flutter run -d windows

# 构建发布版本
flutter build windows
```

## 连接配置

默认连接 `localhost:13145`，可通过应用内设置页面修改目标地址和端口。gRPC 客户端支持自动重连（上限 20 次），超限后 UI 显示重连失败提示。

## 导航页面

| 序号 | 页面 | 说明 |
|------|------|------|
| 0 | Dashboard | 总览仪表盘，显示连接状态和关键指标 |
| 1 | Monitor | 实时传感器数据监控 |
| 2 | Control | 远程控制（方向、站起、坐下等 FSM 动作） |
| 3 | Params | 参数调整（kp/kd 增益等） |
| 4 | Protocol | gRPC 协议调试终端 |
| 5 | IMU | IMU 传感器数据可视化 |
| 6 | History | 推理历史记录查看 |
| 7 | Brain | 智脑页 -- FSM 节点图、运行状态、实时观测向量、策略管理 |
| 8 | OTA | 固件远程更新 |

## 与 han_dog 的关系

sirius 通过 gRPC 连接 `han_dog` 中的 `UnifiedCmsServer`（端口默认 13145）。协议定义在 `han_dog_message` 包中，主要使用的 RPC 包括：

- `Tick` / `Step` -- 仿真时钟驱动
- `Command` -- 发送 FSM 动作
- `ListenImu` / `ListenJoint` / `ListenHistory` -- 流式传感器数据订阅
- `GetProfile` / `SwitchProfile` -- 策略查询和切换

## 开发

```bash
# 代码质量检查（应零 error）
flutter analyze lib/

# 获取依赖
flutter pub get
```

## 技术栈

- Flutter Desktop (Windows)
- gRPC 通信（`han_dog_message` 协议）
- Material Design 3
- 多语言支持（中文 / English）
