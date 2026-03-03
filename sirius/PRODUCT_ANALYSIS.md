# Sirius App — 产品分析报告

**时间**：2026-03-03
**分析范围**：D:\inovxio\brain\brainstem\sirius
**目标**：从操作员视角评估系统功能完整性、用户体验、缺口识别

---

## 1. 核心操作流程分析

### 1.1 典型用户旅程

```
连接 → 初始化 → 控制 → 监控 → 断开
```

#### Step 1: 连接（Dashboard Page）
- **入口**：Sirius App 启动 → Dashboard 页面（sidebar index 0）
- **操作**：
  - 输入机器人 IP（默认 192.168.66.192）和 gRPC 端口（默认 13145）
  - 点击"连接"按钮
  - App 自动保存上次连接的地址（`GrpcService.loadLastConnected()`）
- **体验评价**：✓ 流畅
  - 支持地址自动恢复，降低重复输入成本
  - 连接状态用圆点指示（绿=在线，橙=重连中，灰=离线）
  - **缺点**：IP 输入框没有地址历史记录或扫描功能（LAN 扫描器存在但未集成到 Dashboard）

#### Step 2: 初始化（Dashboard + Control Page）
- **自动步骤**：
  - gRPC 建立连接后，自动订阅 History/IMU/Joint 三个流
  - Brain 加载当前 Profile 对应的 ONNX 模型
  - FSM 初始化为 Zero 状态 → 等待 Init 命令 → Grounded 状态（50Hz 推理开始）
- **用户可见**：
  - Dashboard 显示连接状态、RTT、质量等级（等待 Brain 推理）
  - Control Page 电机使能开关（disabled 直到连接稳定）
- **体验评价**：✓ 自动化程度高
  - **缺点**：无加载进度指示
    - 模型加载失败（如文件不存在）对用户不可见→可能卡顿或无响应
    - 推理启动延迟无提示（用户不知道何时可以操作）

#### Step 3: 操作（Control Page）
- **虚拟摇杆**：
  - 方向控制（X/Y，左摇杆）：100ms 周期发送 Walk(forward, lateral, 0)
  - 旋转控制（Z，右滑块）：0.5x 速度（RT 增益 1.5x）
  - 带 deadzone（0.1）和速度限制（±1.0）
- **行为按钮**：
  - 站立（StandUp）
  - 坐下（SitDown）
  - 电机使能开关
  - 紧急停止（红色大按钮，disable + 停止走路）
- **体验评价**：✓ 直观
  - 虚拟摇杆反应迅速（16ms 节流，实际 100ms 发送）
  - **缺点**：
    - 只有 StandUp/SitDown 两个固定行为，无其他动作库（扶墙、后退等）
    - 没有"空闲"(Idle) 按钮直接触发（需要 5s 无操作）
    - 没有手柄/键盘输入支持（Shell 中有 W/A/S/D 键盘代码，但页面未展示）

#### Step 4: 监控（Monitor/IMU/Brain Page）
- **Monitor Page**：关节实时曲线、超限告警、质量等级、力矩条
- **IMU Page**：加速度/陀螺仪实时波形、RPY 四元数缓存、运动轨迹预览
- **Brain Page**：
  - FSM 状态流可视化（节点图）
  - 推理频率曲线（120 点历史）
  - 策略管理（GetProfile gRPC 列出所有可用 Profile）
  - 策略切换（SwitchProfile RPC，需要机器人在 Grounded 状态）
- **体验评价**：✓ 数据丰富
  - **缺点**：
    - Monitor 页超限告警只显示超过 1.5rad 的轴数，无细节指示哪个轴、超多少
    - IMU 页 RPY 缓存是个体验细节，但没有 quaternion 直观的球形可视化
    - Brain Page 策略切换失败提示（"机器人需处于坐下状态"）但用户可能不知道当前状态

#### Step 5: 断开
- **正常流**：侧边栏 Settings → Logout 或直接关闭 App
- **异常流**：网络中断 → 自动重连（20 次上限，30s 最大退避）
- **体验评价**：✓ 自动恢复机制
  - **缺点**：重连失败上限达到后，UI 显示"重连失败（已达上限）"弹 toast，但没有"手动重新连接"按钮快速恢复

---

## 2. 错误场景处理

### 2.1 模型加载失败
**当前状态**：后端 han_dog.dart 有 3 次重试（2s/4s 退避），失败后禁用电机安全退出
**App 端表现**：
- ✗ 无任何可见反馈
- 推理频率维持 0 Hz
- 用户点击"站立"→ 无反应（命令发出但 Brain 未就绪）

**建议**：
- 在 gRPC 握手阶段检测 Brain.isModelLoaded
- Dashboard 显示"模型加载中..."或"模型加载失败"状态卡片
- 提供"重新加载模型"按钮

### 2.2 关节断联 / IMU 断线
**当前状态**：后端有断线监控，触发 Fault→Transitioning(SitDown)
**App 端表现**：
- Monitor Page 显示"质量等级 C"（红色）
- **缺点**：不显示具体哪个传感器掉线（IMU/Joint 编号）
- Params Page 存在但用户无法编辑和导出参数

### 2.3 网络中断
**当前状态**：gRPC 自动重连（20 次、30s 退避）
**App 端表现**：
- Dashboard 连接状态 → 橙色（isReconnecting）
- RTT 显示为空
- Control Page 所有按钮 disabled
- **缺点**：
  - 重连状态没有重试次数/退避时间显示
  - 无"手动立即重试"按钮
  - 无"设置新地址并重连"快捷操作

### 2.4 策略加载/切换失败
**当前状态**：后端 ProfileManager 有自动回滚机制
**App 端表现**：
- 点击切换 Profile → 旋转 loading indicator
- 失败 → toast "切换策略失败（机器人需处于坐下状态）"
- **缺点**：
  - 消息不够精确（可能是模型加载失败，不是状态问题）
  - 没有显示当前状态和目标状态对比
  - 失败后没有"回滚到上一个 Profile"快捷按钮

---

## 3. 参数调试流程

### 3.1 当前能力
**Params Page** 存在但功能受限：
- **能做**：
  - 查看机器人配置（RobotConfig 数据模型）
  - 修改本地配置并保存为 JSON（export）
  - 加载本地 JSON 配置（import）
  - 预设管理（preset_service.dart）

- **不能做**：
  - ✗ 实时推送修改到机器人（RPC 不存在）
  - ✗ 远程读取当前 Profile 的 kp/kd 增益（gRPC 返回 Params 但只有部分字段）
  - ✗ 在 UI 中编辑 kp/kd，实时观察效果（需要后端支持热加载）

### 3.2 工作流评价
```
用户想调整 kp/kd：
1. 关闭 App，找到 Profile JSON 文件
2. 用文本编辑器修改 Profile
3. 重启 App，切换 Profile → 重新加载
   ↑ 这个流程太繁琐！

理想流程应该是：
1. App 读取当前 Profile 参数
2. 提供 UI 滑块/输入框
3. 实时推送到机器人
4. 观察效果（Monitor 页力矩变化）
5. 满意后"保存为新 Profile"
```

### 3.3 缺口
- **ProfileManager 缺少 gRPC 服务**：
  - `GetCurrentProfile()` — 返回当前 Profile 的所有参数（含 kp/kd）
  - `UpdateGains(kp, kd)` — 实时热更新增益
  - `SaveProfile(name, description)` — 将当前调整保存为新 Profile 文件

---

## 4. 多机型支持（Profile 系统）

### 4.1 当前能力
- **后端**：
  - ProfileManager 管理多个 Profile（Map<String, RobotProfile>）
  - 每个 Profile 包含：模型路径、姿态、增益、缩放参数
  - 支持热加载：han_dog.dart 每 30s 扫描 profileDir，自动添加新 Profile

- **App 端**：
  - Brain Page 显示所有可用 Profile 列表
  - 支持 gRPC SwitchProfile(name)
  - **缺点**：只能列表切换，不能在 App 内创建新 Profile

### 4.2 创建新 Profile 工作流
```
目前没有 UI 支持！用户必须：
1. 找到服务器上的 Profile 目录
2. 复制现有 Profile JSON
3. 修改参数（编程工具）
4. 重启服务器扫描
```

### 4.3 缺口
- **App 端应支持**：
  - 基于当前 Profile 的"另存为"功能
  - 参数编辑器（图形化）
  - 上传新 Profile 到服务器
  - Profile 版本管理/对比

---

## 5. Sirius App 各页面评价

| 页面 | 索引 | 功能 | 体验评分 | 关键缺口 |
|------|------|------|---------|---------|
| **Dashboard** | 0 | 连接管理 | ⭐⭐⭐⭐ | 无 LAN 扫描集成、无地址历史 |
| **Control** | 1 | 遥控操作 | ⭐⭐⭐⭐ | 无其他行为库、键盘走路未展示 |
| **Monitor** | 2 | 关节监控 | ⭐⭐⭐⭐ | 超限告警不详细、无故障诊断 |
| **Params** | 3 | 参数调试 | ⭐⭐ | 无实时热加载、无远程 kp/kd 编辑 |
| **Protocol** | 4 | gRPC 日志 | ⭐⭐⭐ | 日志导出功能可 |
| **IMU** | 5 | IMU 传感 | ⭐⭐⭐ | RPY 计算但无可视化、录制功能完整 |
| **History** | 6 | 运行记录 | ⭐⭐⭐ | CSV 导出功能可 |
| **Brain** | 7 | 智脑策略 | ⭐⭐⭐⭐ | 切换失败信息不清、无回滚快捷 |
| **OTA** | 8 | 固件升级 | ⭐⭐⭐ | 针对 brainstem 的升级流程暂不明确 |

---

## 6. 没有实现但应该有的关键功能

### 6.1 实时参数编辑与热加载（Priority: ⭐⭐⭐⭐⭐）
**痛点**：用户调整 kp/kd 需要关闭应用、编辑文件、重启服务器，周期太长（分钟级）
**方案**：
- 后端：ProfileManager 添加 `updateGains(kp, kd)` RPC，实时推送到 GainManager
- App：Params Page 改造为实时编辑器（滑块/输入框）+ 预览面板（对比原参数）
- 反馈：Monitor 页实时显示力矩变化，让用户立即看到调整效果

**实现复杂度**：Medium（需要后端 gRPC 服务，App 侧 UI 改造）

### 6.2 故障诊断与恢复向导（Priority: ⭐⭐⭐⭐）
**痛点**：机器人异常时（关节超限、IMU 掉线、模型加载失败），用户无法快速定位
**方案**：
- **诊断面板**（新页面 Diagnosis）：
  - 实时检测项：IMU/Joint 连接状态、传感器范围、模型加载状态、推理延迟
  - 告警历史：最近 20 条异常事件（时间、类型、自动恢复情况）
- **恢复向导**：
  - 自动步骤（重启 FSM、清除故障状态、重新连接传感器）
  - 手动步骤（选择恢复策略：soft/hard reset）

**实现复杂度**：Medium（后端已有监控逻辑，App 侧需 UI 组织）

### 6.3 配置对比与版本管理（Priority: ⭐⭐⭐⭐）
**痛点**：多个 Profile 时，用户不清楚参数差异（kp/kd 是否改了、模型路径是否一样）
**方案**：
- **Profile 对比页**：选择两个 Profile，并排显示所有参数（标红差异）
- **版本历史**：记录每个 Profile 的修改时间、修改者、变更内容
- **模板市场**：预置几个常见 Profile（敏捷型/稳定型/省电型），用户可快速复制并微调

**实现复杂度**：Medium（需要后端存储 Profile 历史，App 侧 UI 对比）

### 6.4 在线参数编辑与上传（Priority: ⭐⭐⭐）
**痛点**：创建新 Profile 必须找服务器的文件系统，不方便
**方案**：
- **Profile 编辑器**（在 Params 页集成）：
  - 图形化编辑所有参数（无需 JSON 语法知识）
  - "另存为"新 Profile → 直接上传到机器人（via gRPC）
  - 服务器自动保存为 JSON 到 profileDir

**实现复杂度**：Medium-High（需要后端 SaveProfile RPC + 文件系统操作）

### 6.5 运动轨迹规划与预演（Priority: ⭐⭐⭐）
**痛点**：用户无法提前看到机器人会如何走路（尤其是新 Profile）
**方案**：
- **轨迹预演器**（新页面 Trajectory）：
  - 选择行为（Walk/StandUp/SitDown）
  - 设置参数（速度、方向、duration）
  - 显示 3D 骨骼动画预演（后端通过 gRPC 返回历史帧序列）
  - 允许暂停/慢放/反向播放

**实现复杂度**：High（需要 3D 渲染库、后端记录完整历史）

---

## 7. 系统整体评价

### 7.1 优势
- ✓ 核心流程（连接→操作→监控）完整且易用
- ✓ 自动重连机制稳定（20 次尝试、指数退避）
- ✓ 多 Profile 支持，热加载机制
- ✓ 监控数据丰富（关节、IMU、力矩、推理频率）
- ✓ 协议日志完整，方便调试

### 7.2 劣势
- ✗ **参数调试流程过于繁琐**（关闭 App → 编辑文件 → 重启）
- ✗ **故障定位困难**（无诊断工具、告警不详细）
- ✗ **新 Profile 创建无 UI 支持**（需要手工编辑 JSON）
- ✗ **模型加载进度不可见**（用户不知道何时可操作）
- ✗ **切换失败信息不清晰**（消息不够精确、无回滚快捷）

### 7.3 用户满意度预估
- **初期用户**（一键连接、按钮操作）：⭐⭐⭐⭐ (4/5)
- **调试用户**（调整参数、诊断故障）：⭐⭐ (2/5)
- **维护人员**（管理多机、版本控制）：⭐ (1/5)

---

## 8. 建议优先级排序

### 立即实施（1-2 周）
1. **模型加载进度提示**（Dashboard 显示"加载中"）
2. **关节超限告警详情**（Monitor 页标注哪个轴、超多少）
3. **重连失败快捷操作**（"手动重试"按钮）

### 短期计划（3-4 周）
4. **实时 kp/kd 热加载**（后端 RPC + App 编辑器）
5. **故障诊断面板**（检测项 + 恢复向导）
6. **Profile 对比工具**（并排显示参数差异）

### 中期计划（5-8 周）
7. **在线 Profile 创建与上传**
8. **运动轨迹预演**（3D 预演 or 2D 动画）

---

## 9. 技术建议

### 后端（brainstem/han_dog）
```dart
// 新增 gRPC 服务（cms.proto + unified_cms_server.dart）
service Cms {
  // 已有
  rpc Subscribe(Empty) returns (stream History);
  rpc Walk(WalkCmd) returns (Empty);
  rpc StandUp(Empty) returns (Empty);
  rpc SitDown(Empty) returns (Empty);
  rpc GetProfile(Empty) returns (ProfileInfo);
  rpc SwitchProfile(ProfileName) returns (Empty);

  // 新增 ↓
  rpc GetCurrentGains(Empty) returns (GainsInfo);           // 返回当前 kp/kd
  rpc UpdateGains(GainsCmd) returns (Empty);                // 热更新增益
  rpc GetDiagnostics(Empty) returns (DiagnosticsInfo);      // 传感器状态、告警
  rpc SaveProfile(ProfileData) returns (ProfileName);       // 保存新 Profile
  rpc GetProfileList(Empty) returns (ProfileListResp);      // 详细 Profile 列表（含版本）
  rpc CompareProfiles(CompareReq) returns (CompareResp);    // 对比两个 Profile
}
```

### App（sirius）
```dart
// 新页面
pages/diagnostics_page.dart       // 故障诊断
pages/trajectory_preview_page.dart // 轨迹预演
pages/profile_editor_page.dart     // Profile 编辑器

// 服务扩展
services/grpc_service.dart
  + updateGains(kp, kd)
  + getDiagnostics()
  + saveProfile(name, profileData)

// Widget 改造
pages/params_page.dart → 实时编辑器（滑块 + 对比预览）
pages/dashboard_page.dart → 模型加载进度
pages/monitor_page.dart → 关节超限详情
```

---

## 10. 附录：用户访谈建议清单

如果后续有机会做用户调研，建议问以下问题：

1. 你多久调整一次 kp/kd？调整流程有多痛苦（1-10 分）？
2. 机器人异常时，你如何诊断（看日志、观察行为、询问工程师）？
3. 你管理几个 Profile？如何区分它们（参数记在脑子里？笔记？）？
4. 有没有想过 App 缺少什么功能最着急？
5. 对 3D 运动预演感兴趣吗？

---

**报告完成**
灵犀（产品分析师）
2026-03-03
