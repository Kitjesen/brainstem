# H15/H18 策略零点与无冲击接管设计

日期：2026-07-26
目标分支：`bodyheightctrl`

## 1. 背景与证据

H15/H18 ONNX 训练时使用的腿部默认关节零点为：

```text
FR [-0.1, -1.1,  2.6]
FL [ 0.1,  1.1, -2.6]
RR [ 0.1,  1.1, -2.6]
RL [-0.1, -1.1,  2.6]
```

机器人当前 L1 安全站姿来自 master：

```text
FR [-0.1, -0.8,  1.8]
FL [ 0.1,  0.8, -1.8]
RR [ 0.1,  0.8, -1.8]
RL [-0.1, -0.8,  1.8]
```

现有 `standingPose` 同时承担 L1 目标、策略观测零点和 ONNX
动作偏置。将其整体替换为 master 站姿后，破坏了 ONNX 的训练接口。
实机 CSV 显示，体高命令仅变化约 0.12 mm 时，进入 Walking 的首帧
单腿目标仍跳变 0.60–0.86 rad，机身横滚在约 1.4 s 内增至约 15°。

## 2. 范围

本次实现包含：

- 分离物理站立目标和 ONNX 策略零点；
- H15/H18 默认体高改为 0.40 m；
- BodyHeight 遥控模式从 Standing 进入 Walking 时进行 2 s 无冲击接管；
- 接管期间保持零速度和 0.40 m 体高命令；
- 同步平滑切换关节目标和 Kp/Kd；
- 对旧 profile 保持向后兼容；
- 完成单元、回归、ONNX 和离线仿真验证。

本次不包含：

- 修改 ONNX；
- 实机自动使能、站立、行走或体高命令；
- 直接下调 Walking Kp/Kd；
- 更改 H15/H18 的 58/580 维观测结构；
- 更改体高范围 0.20–0.54 m 或遥控调节速率 0.02 m/s。

## 3. Profile 契约

`RobotProfile` 增加两个明确语义：

- `standUpPose`：L1/R1 固定站立轨迹的物理目标；
- `policyDefaultPose`：策略关节相对观测和 ONNX 动作反归一化的零点。

旧 `standingPose` 字段继续作为兼容字段：

- 未提供 `standUpPose` 时，回退到 `standingPose`；
- 未提供 `policyDefaultPose` 时，回退到 `standingPose`；
- 现有 57 维策略无需修改即可保持原行为。

H15/H18 profile 同时保留 legacy `standingPose`，以便旧程序回滚时仍可
加载；其值与 `standUpPose` 相同，均为 master 安全站姿。
`policyDefaultPose` 使用训练值 `±1.1/±2.6`。

策略计算必须满足：

```text
q_relative = q_actual - policyDefaultPose
q_policy   = policyDefaultPose + actionScale * onnx_action
```

StandUp 插值只使用 `standUpPose`，不得再改变策略零点。

## 4. 2 秒无冲击接管

仅对 `observationType == bodyHeight` 的 H15/H18 启用。
一次接管持续 100 个实际下发控制间隔，按 50 Hz 计为 2 s。
端点包含第 0 帧和第 100 帧；未使能电机或未实际下发动作时不推进
接管进度。

当云卓遥控器在 Standing 状态通过左摇杆或右侧体高轴请求进入 Walking：

1. 记录当时实测关节位置 `q_start`；
2. 将 FSM 请求固定为 `Walking(0,0,0)`；
3. ONNX 继续每帧推理，但输出先经过平滑混合；
4. 体高命令在接管完成前固定为 profile 默认值 0.40 m；
5. 忽略接管期间的速度和体高增量，控制器持续维持零速度；
6. 第 100 个实际控制帧后开放左摇杆速度和右摇杆体高调节。

平滑系数采用端点速度为零的 smoothstep：

```text
s = clamp(frame / 100, 0, 1)
alpha = 3*s^2 - 2*s^3
```

腿部位置目标：

```text
q_command = lerp(q_start, q_policy, alpha)
```

轮速目标：

```text
wheel_command = alpha * wheel_policy
```

增益同步混合：

```text
Kp = lerp(standUpKp, inferKp, alpha)
Kd = lerp(standUpKd, inferKd, alpha)
```

在首个实际下发帧，位置目标等于 `q_start`，因此位置误差不发生阶跃；
在最后一帧，目标和增益完全切换到策略值。

## 5. 中断和异常行为

- R1/L1 返回 Standing：立即取消接管，交由既有 StandUp 流程；
- L2 趴下：立即取消接管，交由既有 SitDown 流程；
- 红键或 H 断使能：立即保留既有断使能行为，不被接管阻塞；接管暂停，
  重新使能后的首帧重新采集实际关节位置并从第 0 帧开始；
- 状态离开 Walking：取消未完成接管；
- 推理、传感器或电机健康检查失败：继续使用现有故障处理路径；
- 接管期间不得缓存并在结束瞬间补发旧摇杆命令；
- gRPC 与遥控器优先级规则保持不变。

## 6. 默认体高

H15/H18 的 `bodyHeightCommand` 从 0.35 m 改为 0.40 m。
0.40 m 位于训练范围 0.20–0.54 m 内，并与当前 L1 实际站立高度接近。
R1 重置时同样回到 0.40 m。接管完成后，右摇杆仍以 0.02 m/s 连续调节。

0.40 m 是策略命令，不是额外的实测高度传感器读数。

## 7. 测试与验收

### Profile/策略契约

- legacy profile 只含 `standingPose` 时行为不变；
- H15/H18 分别解析出安全 `standUpPose` 和训练 `policyDefaultPose`；
- StandUp 使用安全姿态；
- observation 和 `toRealAction/fromRealAction` 使用训练零点；
- H15 保持 58 维，H18 保持 580 维。

### 接管单元测试

- 第 0 帧目标等于实测起点；
- 第 50 帧 smoothstep 权重为 0.5；
- 第 100 个控制间隔完全等于实时策略目标；
- Kp/Kd 与动作使用同一权重；
- 轮速从 0 平滑接入；
- 未实际下发时不推进；
- Standing/SitDown/故障可取消或抢占；
- Disable 立即生效并暂停接管，重新使能后从新的实测位置重新开始；
- 接管期间速度为零、体高保持 0.40 m；
- 完成后恢复遥控速度和体高调节。

### 回归和离线验证

- 使用已采集首帧数据验证修复后每腿最大目标跳变不超过 0.25 rad；
- H15/H18 ARM64 ONNX smoke test 通过；
- Dart 全量测试和静态分析通过；
- MuJoCo 的 0.40 m、零速度进入场景无倾倒、无明显左右偏置；
- 不通过脚本或测试发送任何实机使能或运动命令。

## 8. 部署约束

代码先在本地 `bodyheightctrl` 工作副本完成并验证，再同步到：

```text
/home/bsrl1/brainstem-bodyheightctrl
```

同步后只允许运行不访问硬件的 Dart 单元测试和 ONNX smoke test。
不得执行 `bodyheight_service.sh start h15/h18`，不得重启当前服务，
不得使能电机。最终实机测试由用户明确下令并亲自操作。
