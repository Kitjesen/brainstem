# Brainstem 版本与兼容性

> 版本: 1.0.0 | 日期: 2026-04-04

---

## 版本号规则

Brainstem 遵循语义化版本 (SemVer):

```
MAJOR.MINOR.PATCH
  |     |     |
  |     |     └── 向后兼容的 bug 修复
  |     └──────── 向后兼容的新功能
  └────────────── 不兼容的 API 变更
```

---

## 稳定 API（v1.0.0 起冻结）

以下接口已固化，承诺向后兼容。客户基于这些接口编写的代码**不会因升级而失效**。

### gRPC API (cms.proto v1.0.0)

| RPC | 签名 | 状态 |
|-----|------|------|
| Enable | `() -> Empty` | 冻结 |
| Disable | `() -> Empty` | 冻结 |
| Walk | `Vector3 -> Empty` | 冻结 |
| StandUp | `() -> Empty` | 冻结 |
| SitDown | `() -> Empty` | 冻结 |
| GetCmsState | `() -> CmsState` | 冻结 |
| ListenCmsState | `() -> stream CmsState` | 冻结 |
| ListenImu | `() -> stream Imu` | 冻结 |
| ListenJoint | `() -> stream Joint` | 冻结 |
| ListenHistory | `() -> stream History` | 冻结 |
| GetParams | `() -> Params` | 冻结 |
| GetVoltage | `() -> Voltage` | 冻结 |
| GetMotorStatus | `() -> MotorStatusResponse` | 冻结 |
| ClearMotorFault | `ClearFaultRequest -> Empty` | 冻结 |
| SetZero | `() -> Empty` | 冻结 |
| SwitchProfile | `ProfileRequest -> ProfileInfo` | 冻结 |
| GetProfile | `() -> ProfileInfo` | 冻结 |
| GetStartTime | `() -> Timestamp` | 冻结 |
| Tick | `() -> History` | 冻结 (仿真专用) |
| Step | `SimState -> Empty` | 冻结 (仿真专用) |

**兼容性承诺:**
- 现有 RPC 的签名和语义不变
- 现有 message 的字段编号不变
- 新增 RPC 和字段使用新编号，不影响已有客户端
- 废弃功能保留至少 2 个大版本
- 破坏性变更只在 v2.0.0 发生

### FSM 状态定义

| 状态 | 枚举值 | 含义 | 冻结 |
|------|--------|------|------|
| Zero | 0 | 初始化中 | 冻结 |
| Grounded | 1 | 坐姿，安全状态 | 冻结 |
| Standing | 2 | 站立，可接收运动指令 | 冻结 |
| Walking | 3 | 行走中 | 冻结 |
| Transitioning | 4 | 过渡动作中 (站起/坐下) | 冻结 |

状态转换规则不变: Grounded <-> Standing <-> Walking。

### 关节编号

| 索引 | 关节 | 冻结 |
|------|------|------|
| 0-2 | 前右 (FR) 髋/大腿/小腿 | 冻结 |
| 3 | 前右 (FR) 足轮 | 冻结 |
| 4-6 | 前左 (FL) 髋/大腿/小腿 | 冻结 |
| 7 | 前左 (FL) 足轮 | 冻结 |
| 8-10 | 后右 (RR) 髋/大腿/小腿 | 冻结 |
| 11 | 后右 (RR) 足轮 | 冻结 |
| 12-14 | 后左 (RL) 髋/大腿/小腿 | 冻结 |
| 15 | 后左 (RL) 足轮 | 冻结 |

### 坐标系约定

| 轴 | 方向 | 冻结 |
|----|------|------|
| x | 前进为正 | 冻结 |
| y | 向左为正 | 冻结 |
| z | 向上为正 | 冻结 |
| walk(vx) | 正=前进，负=后退 | 冻结 |
| walk(vy) | 正=左移，负=右移 | 冻结 |
| walk(vyaw) | 正=逆时针，负=顺时针 | 冻结 |

### 传感器接口

| 接口 | 数据 | 单位 | 冻结 |
|------|------|------|------|
| ImuService | gyroscope | rad/s, body frame | 冻结 |
| ImuService | quaternion | Hamilton (w,x,y,z), world->body | 冻结 |
| JointService | position | rad | 冻结 |
| JointService | velocity | rad/s | 冻结 |
| JointService | torque | N*m | 冻结 |

### Profile JSON 格式

Profile 文件的 JSON Schema 已发布: `sdk/python/docs/profile_schema.json`

必填字段和含义不变。新增字段使用可选字段，不影响已有 profile 文件。

### Python SDK (brainstem-sdk)

`ThunderClient` 的全部公开方法签名冻结，与 gRPC API 一一对应。

---

## 可变部分（不承诺兼容）

以下参数和实现可能随版本更新而变化。客户代码不应硬编码这些值。

| 项目 | 原因 | 建议 |
|------|------|------|
| PD 增益 (Kp/Kd) | 随电机调参和策略训练调整 | 通过 Profile 配置，不硬编码 |
| ONNX 模型文件 | 持续训练迭代 | 通过 Profile.modelPath 引用 |
| 低压阈值 (当前 42V) | 电池型号可能变 | 通过环境变量配置 |
| 控制频率 (当前 50Hz) | 未来可能提升 | 不假设固定周期 |
| actionScale 参数 | 随训练策略变化 | 通过 Profile 配置 |
| standUpCounts/sitDownCounts | 可调整过渡速度 | 通过 Profile 配置 |
| 环境变量名 (HAN_DOG_*) | 内部实现细节 | 仅运维使用，不在客户代码中引用 |
| Dart 内部实现 | 随时重构 | 客户只通过 gRPC/SDK 交互 |

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0.0 | 2026-04-04 | 首次正式发布。20 个 gRPC RPC 冻结，Python SDK v1.0.0，Profile JSON Schema 发布 |
