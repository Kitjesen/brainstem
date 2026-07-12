# 电机输出安全修复记录

日期：2026-07-12
范围：`han_dog` 真机控制链路

## 问题原因

原来的 CMS/FSM 状态与真实电机输出是两条独立链路。电机未使能时，`StandUp` 仍会推进状态机并写入站立目标；随后按下 Enable 会同时打开扭矩和动作输出，下一帧便可能把“站立目标”直接施加到仍趴地的关节，造成瞬间大位置误差和蹦起。

正常操作顺序应为：**物理趴地且 CMS 为 Grounded → Enable → StandUp**。

## 统一后的安全边界

`MotorOutputController` 是真机常规路径中唯一可以改变全局电机输出状态的入口。

- 输出动作门在 Disable CAN 请求发出前立即关闭；请求失败时，门保持关闭。
- Enable、Disable 和维护操作均串行执行。
- Enable 前先下发“当前位置保持”目标，再开扭矩；准备期间收到 Disable 时，旧 Enable 会被取消，不能再发 Enable 帧。
- Enable 局部失败时会 best-effort 补发全局 Disable；在 Disable 请求未成功完成前，所有后续 Enable 都被拒绝。
- 校零、单关节清故障和自动故障恢复都必须先在同一串行队列中完成 Disable 请求，不能把“软件门已关”当作“已经断扭矩”。
- gRPC 硬件模式未注入共享输出控制器时，Enable/SetZero 直接拒绝，避免回退到旁路实现。

## Enable 前置条件

`MotorEnableSafety` 会依次检查：

1. CMS 必须为 `Grounded`。
2. 12 个腿部关节反馈频率至少为 50 Hz，位置和速度均为有限数。原始 CAN 顺序为每腿 `[hip, thigh, calf, foot]`，检查索引固定为 `[0,1,2,4,5,6,8,9,10,12,13,14]`，不会把足轮误当成腿关节。
3. 腿部关节未超过 `HAN_DOG_JOINT_LIMIT_RAD`，速度不超过 0.5 rad/s。
4. 腿部关节相对当前 Profile 的 `sittingPose` 不超过 `HAN_DOG_ENABLE_POSE_TOLERANCE_RAD`（默认 0.35 rad）。
5. 没有待恢复的电机故障。
6. 控制权仲裁允许请求来源；YUNZHUO 持有时 gRPC 不可 Enable。
7. 没有低压锁定，且此前的物理 Disable 状态已确认。

四个连续旋转足轮（索引 12–15）不参与角度和趴地姿态窗口检查。

## 同类入口处理

| 入口 | 处理 |
| --- | --- |
| gRPC Enable/Disable | 使用共享输出控制器；硬件模式缺少该控制器时拒绝 Enable。 |
| 遥控器 H Enable | 使用共享输出控制器，并同步手柄本地开关状态。 |
| 红键急停 | 立即关闭动作门，再发送 `disable(clearErrors: true)`。 |
| ClearMotorFault（全量/指定关节） | 全量清故障经统一 Disable；指定关节先全局物理 Disable，再进入维护队列清除。 |
| gRPC / 遥控器 SetZero | 仅允许 Grounded 且已确认物理断扭矩时执行。 |
| MotorHealth critical fault | 立即通过共享输出控制器 Disable；自动恢复也通过 Disable 后维护队列。 |
| 低压 | 首次检测即锁定本进程后续 Enable；趴地完成或超时后统一 Disable。 |
| Profile 切换 | 仅允许 `Grounded`，不允许站立中切模型、姿态或增益。 |
| 正常关机 | 经共享输出控制器 Disable；启动早期失败和进程级崩溃保留直接物理 Disable 作为最终兜底。 |

## 自动化验证

已覆盖以下回归场景：

- Enable 准备期间 Disable 的竞态，以及 Enable 局部失败后的物理回滚。
- 物理 Disable 失败后，校零/维护绝不执行。
- 红键、全量和指定关节清故障均关闭共享输出门。
- 带扭矩校零拒绝、未接入共享控制器的硬件 Enable 拒绝。
- 关键电机故障立即 Disable，恢复时 Disable 失败不会发送单关节清故障命令。
- 低压锁定、未恢复故障、姿态窗口、反馈频率、速度和仲裁拒绝。
- 站立状态切换 Profile 被拒绝。

本次验证结果：

- `dart test han_dog/ han_dog_brain/ frequency_watch/ skinny_dog_algebra/`：265 项通过。
- `dart analyze han_dog_brain/ han_dog/`：零问题。

## 上机注意事项与剩余风险

自动化测试不替代真机验证。上机时应在低空、空载、可立即急停的条件下，依次验证正常 Enable、错误姿态拒绝、红键、低压锁定、故障恢复和遥控/远程仲裁冲突。

当前板端 `mini` Profile 的 `sittingPose` 为全零；首次部署前必须在**电机输出关闭**的状态下读取 Grounded 关节遥测，确认 12 个腿关节均落在 `HAN_DOG_ENABLE_POSE_TOLERANCE_RAD`（默认 0.35 rad）范围内。若不在范围内，应修正 Profile 的 `sittingPose` 或重新标定零位，不能为绕过拒绝而放宽或移除该安全门。

当前 gRPC 服务仍监听 `0.0.0.0`，且该服务本身未实现认证或 TLS。因此真机只能部署在可信隔离网络中；若要暴露到更广网络，需要另行确定认证、TLS 和绑定地址策略。

### Disable 完成语义

当前 `RealJoint.disable()` 会把 Disable 帧投递到 CAN 队列后返回，尚未等待来自每台电机的 Disable ACK 或状态回执。因此 `MotorOutputController` 的“Disable 已完成”表示**软件串行队列与 CAN 请求已成功提交**，并不等同于已由硬件遥测确认全部电机无扭矩。该控制器仍会在请求前关闭软件动作门，并在请求失败时禁止后续 Enable；若需要硬件级确认，应在 `RealJoint` 增加电机 ACK/状态回执验证后再提升这一保证等级。
