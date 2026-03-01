## 1.1.0

### 新增页面
- **智脑页（`brain_page.dart`）**：FSM 状态节点图（动画高亮）、运行状态卡片（FSM/推理/IMU/关节频率 + 趋势折线）、实时观测向量（指令/陀螺仪/重力/关节位置/上一步动作）、策略管理（GetProfile/SwitchProfile gRPC）
- **IMU 姿态页（`imu_page.dart`）**：Roll/Pitch/Yaw 圆弧刻度仪表（CustomPaint）、陀螺仪三轴时序折线图（200帧滚动窗口）、人工地平仪（天地旋转+俯仰平移）、投影重力 2D 指示器
- 侧边栏（`sidebar.dart`）新增「姿态」「记录」「智脑」三个导航项（共 9 项）

### 新增功能
- **电机状态解码**（`utils/motor_status.dart`）：G6620 状态码 → 中文描述 + 颜色（正常/禁用/过压/欠压/过流/过温/通信丢失/过载）；关节监控页各关节新增状态徽章列
- **推理增益实时展示**（`params_page.dart`）：`_InferenceGainCard` 按 FL/FR/RL/RR 分组展示 16 关节 Kp/Kd 均值，来源 `latestHistory.kp/kd`
- **Action vs Position 误差可视化**（`brain_page.dart`）：`_ErrorMatrixGrid` 展示 `action − pos` 16 个关节差值，`|误差| > 0.3 rad` 橙色加粗高亮
- **运行记录页（`history_page.dart`）**：历次连接会话记录、最近 10 次时长柱状图、当前会话实时时长更新

### gRPC 服务（`grpc_service.dart`）
- **重连上限**：`_maxReconnectAttempts = 20`（指数退避 1s→30s），超限后设 `_reconnectLimitReached`，`healthStatus` 显示「重连失败（已达上限 20 次）」并调用 `onErrorNotify`；`connect()` / `disconnect()` 时自动重置
- **策略接口**：`_fetchProfile()` / `switchProfile(name)` — 连接成功后自动拉取，断开时清空
- `healthStatus` 全部中文化（已断开 / 重连中 / 无数据 / 正常 / 重连失败）
- 新增 `reconnectLimitReached` getter 供 UI 判断状态

### 国际化（`app_localizations.dart`）
- 新增 `navImu`（姿态）、`navHistory`（记录）、`navBrain`（智脑）

## 1.0.0

- Initial version.
