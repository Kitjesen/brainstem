# Body-height 遥控器模式设计

## 目标

为云卓遥控器增加一套由活动策略自动选择的按键模式：

- 普通策略继续使用原有 `LegacyRemoteMode`，行为保持不变。
- `observationType == "bodyHeight"` 的 H15/H18 使用
  `BodyHeightRemoteMode`。
- Body-height 模式保留原有左摇杆速度、右摇杆左右偏航、
  R1/R2、CH5 和急停功能，并将原本未使用的右摇杆上下轴用于连续
  调节体高。

本功能不新增 systemd 服务、gRPC 接口或外部依赖。

## 模式选择

机器人仍然只运行一个 `han-dog-bodyheight.service`。启动命令决定初始
profile：

```bash
./scripts/bodyheight_service.sh start h15
./scripts/bodyheight_service.sh start h18
```

服务读取活动 `RobotProfile.observationType` 后自动选择遥控器模式：

```text
observationType == bodyHeight  -> BodyHeightRemoteMode
其他 observationType          -> LegacyRemoteMode
```

H15 和 H18 都进入 `BodyHeightRemoteMode`。两者历史维度不同，仍必须通过
停止并重启服务切换，不允许通过 R2 进行 H15/H18 热切换。

## 组件边界

### RealController

`RealController` 继续只负责解析云卓 SBUS 数据并提供标准化输入流。它新增
或公开右摇杆 Y 轴流，但不知道活动 profile、FSM 状态、体高范围或 ONNX
模型。

### RealControlDog

`RealControlDog` 保留跨模式一致的安全和生命周期职责：

- CH5 电机使能/禁用；
- 红键急停；
- 遥控器断连故障处理；
- 标零组合键；
- R2 profile 切换请求；
- 创建、切换并释放当前遥控器模式。

体高积分、状态转换和 profile 能力判断不直接堆入
`RealControlDog`。

### RemoteControlMode

引入一个内部遥控器模式接口，至少提供：

```text
start()
updateProfile(profile)
dispose()
```

模式必须拥有并释放自身的 stream subscription、50 Hz 定时器和临时状态。
切换模式时先释放旧模式，再创建新模式，禁止旧订阅继续发送命令。

### LegacyRemoteMode

完整保留当前 master 的运动映射和语义，不读取右摇杆 Y 轴，不改变 57 维
策略行为。

### BodyHeightRemoteMode

在原运动映射基础上增加右摇杆体高控制。所有 FSM 命令都通过现有
`ControlArbiter.command(..., ControlSource.yunzhuo)`，不得直接修改
`Brain` 或绕过仲裁器。

## Body-height 模式按键映射

```text
左摇杆上下       -> vx
左摇杆左右       -> vy
右摇杆左右       -> yaw（保留现有逻辑）
右摇杆上下       -> 连续调节体高
L1/L2            -> 保留现有站立/坐下功能
R1               -> 返回 Standing
R2               -> 保留现有 profile 切换入口
CH5              -> 电机使能/禁用
红键             -> 急停
```

左摇杆速度和右摇杆体高可同时使用。体高控制进入 `Walking` 后只发送
`SetBodyHeight` 动作，不持续发送 `Walk(0,0,0)`，因此不会覆盖左摇杆的
`Walk(vx, vy, yaw)`。

## 体高轴处理

右摇杆 Y 轴范围为 `[-1, 1]`：

- 上推为增加体高；
- 下拉为降低体高；
- 死区为 `0.10`；
- 死区外线性重映射到 `[-1, 1]`，避免跨过死区时产生阶跃；
- 满量程体高变化率为 `0.08 m/s`；
- 以 50 Hz 更新；
- 使用实际单调时间计算增量，并限制单次时间步，避免调度暂停后产生大跳变；
- 最终目标始终限制在活动 profile 的
  `[minBodyHeightCommand, maxBodyHeightCommand]`。

计算语义为：

```text
heightDelta = remappedAxis * 0.08 m/s * boundedDeltaTime
nextTarget  = clamp(currentTarget + heightDelta, profileMin, profileMax)
```

摇杆回中后不继续发送体高更新，保留最后目标值。

## FSM 行为

### Grounded、Zero 和 Transitioning

右摇杆体高轴被忽略。模式本身不会在启动、趴地和站起/坐下过渡期间修改
体高目标；服务启动值来自活动 profile，当前 H15/H18 均为 `0.35 m`。
现有 gRPC `SetBodyHeight` 的状态规则保持不变，不属于本遥控器模式的限制。

### Standing

右摇杆 Y 轴首次离开死区时，模式通过仲裁器发送一次
`Walk(0,0,0)`，使 FSM 进入 `Walking`。该次触发不重复发送，也不覆盖
随后来自左摇杆的速度。

待 FSM 确认为 `Walking` 后，下一次 50 Hz 更新才开始改变体高，避免在
状态切换尚未完成时丢失命令。

### Walking

右摇杆按 `0.08 m/s` 更新体高，左摇杆继续独立控制速度。右摇杆回中后
只停止体高变化，不改变 FSM，也不覆盖左摇杆速度；左摇杆同时回中时保持
`Walking(0,0,0)` 和当前体高。不会自动返回 `Standing`。

### R1 返回 Standing

R1 保留原有“停止策略行走并返回 Standing”功能。Body-height 模式标记
一次待重置操作；FSM 确认进入 `Standing` 后，通过仲裁器把体高目标重置为
活动 profile 的 `bodyHeightCommand` 默认值。当前 H15/H18 为 `0.35 m`。

重置发生在进入 `Standing` 后，避免在退出 Walking 前让策略目标突然跳变。

## 控制权仲裁

保持现有规则：

- 云卓遥控器始终可以抢占 gRPC；
- gRPC 不能抢占活动的云卓控制；
- 所有右摇杆体高动作使用 `ControlSource.yunzhuo`；
- 遥控器控制期间，gRPC 体高命令可能被静默拒绝，现有上位机客户端继续通过
  telemetry confirmation 将这种拒绝报告为失败；
- 不拆分速度和体高控制权，不采用“后发送者覆盖”规则。

## Profile 切换

模式使用活动 `RobotProfile` 提供的：

- `observationType`；
- 默认体高；
- 最小/最大体高；
- 速度范围及现有增益。

当兼容的 profile 切换发生时：

1. 停止旧模式的轴订阅和定时器；
2. 更新模型、增益、速度范围和体高范围；
3. 将体高目标设置为新 profile 默认值；
4. 根据新 profile 的 `observationType` 创建对应模式。

任何模型输入形状不兼容的切换继续由现有 ProfileManager 拒绝。H15/H18
之间仍使用服务重启切换。

## 故障和安全行为

- 遥控器数据超过现有 `150 ms` watchdog 时限未更新，体高轴立即归零并
  停止积分；
- 非有限摇杆值或体高值被拒绝，保留最后安全目标；
- profile 范围无效时 Body-height 模式不得启动；
- 模式 subscription 出错时沿用现有 controller fault 路径；
- 电机使能、急停和低压保护行为不因模式切换而改变；
- 模式切换或服务停止必须释放所有定时器和订阅；
- 本功能不自动使能电机，也不自动发送站立命令；
- 在电机使能后，即使速度为零，进入 `Walking` 并改变体高也会产生真实运动。

## 测试

实现前先增加回归测试，覆盖：

1. Legacy 模式的现有按键映射完全不变；
2. `bodyHeight` profile 自动选择 Body-height 模式；
3. 非 body-height profile 不订阅右摇杆 Y 轴；
4. `0.10` 死区内不产生体高命令；
5. 死区外线性映射和 `0.08 m/s` 时间积分正确；
6. 调度时间步被限制，不会产生单次大跳变；
7. profile 最小/最大体高边界正确；
8. Grounded、Zero、Transitioning 状态忽略体高轴；
9. Standing 第一次推动只触发一次 `Walk(0,0,0)`；
10. Walking 中体高更新不覆盖左摇杆速度；
11. 左摇杆速度和右摇杆体高可同时工作；
12. 回中保持 Walking 和最后体高；
13. R1 返回 Standing 后重置 profile 默认体高；
14. 遥控器保持 gRPC 之上的仲裁优先级；
15. 遥控器断连后体高积分停止；
16. profile/mode 切换释放旧订阅和定时器；
17. H15 与 H18 都选择 Body-height 模式；
18. 现有 Dart、Python、ONNX smoke 和服务脚本测试继续通过。

自动测试不得连接真实设备、使能电机或发送真实运动命令。实机验证只能在
机器人可靠支撑、轮子离地且急停可用时，从低幅度右摇杆输入开始。
