# MuJoCo 仿真踩坑记录

> 策略在 Isaac Lab (PhysX) 训练，MuJoCo 中验证时遇到的问题及根因。

---

## Bug 1: Memory 初始值导致策略失效（最严重）

**现象**: 机器人站立阶段塌陷（高度 0.41→0.23），Walking 速度只有命令值的一半。

**根因**: brainstem 将 Memory 初始 `action`/`nextAction` 设为 `standingPose`，训练时初始值是**零矩阵**。

```dart
// 错误
action: standingPose, nextAction: standingPose
// 正确（和训练一致）
action: JointsMatrix.zero(), nextAction: JointsMatrix.zero()
```

**原理**: obs 里 `last_action = (action - standingPose) / actionScale`。初始值为 standingPose 时结果=0，零矩阵时结果=大负值。策略训练时看到的是后者。5 帧 history 全被污染，策略从第一帧就在陌生的状态空间运行。

同理 `initialPosition` 和 `initialProjectedGravity` 也必须和训练一致（零矩阵 / 零向量），不能用"物理上更正确"的值。

---

## Bug 2: clampAction 破坏闭环反馈

**现象**: Walking 时策略输出保守，速度不达标。

**根因**: brainstem 加了逐关节 clamp（hip±0.5, thigh±1.5 等），训练时**没有 clamp**。

```dart
// 错误
JointsMatrix clampAction(JointsMatrix action) => action.clampPerJoint(...);
// 正确
JointsMatrix clampAction(JointsMatrix action) => action; // no-op
```

**原理**: clamp 截断策略输出后存入 history，下一帧 obs 里的 `last_action` 和策略实际命令不一致。策略的内部模型被破坏——"我以为我发了 X，但实际发了 clamp(X)"，导致输出越来越保守。

---

## Bug 3: 策略输出和物理目标耦合

**现象**: Idle/StandUp 阶段 obs 里 `last_action` 全零，进入 Walking 后策略需要几秒"热身"。

**根因**: `Behaviour.next()` 用 `memory.latestAction`（= 上一帧 nextAction = 物理目标）作为 obs 的 action 字段。Idle 的物理目标是 standingPose，obs 里 action = 0。训练时每帧都跑策略，`last_action` 是真实 ONNX 输出。

**修复**: 引入 `PolicyActionTracker`，分离策略输出（给 obs）和物理目标（给电机）：
- Walk: policyTracker = ONNX 输出，nextAction = ONNX 输出（两者一致）
- Idle: policyTracker = ONNX 输出（通过 inferAction），nextAction = standingPose（物理不变）

---

## Bug 4: PD 控制频率太低

**现象**: 机器人站立就塌，Walking 不稳。

**根因**: 20 个 MuJoCo substep 共用一个 tau，PD 频率 = 50Hz。应该每步都算 PD（200Hz）。

```python
# 错误: PD 只算一次，20 步共用
tau = kp * (target - q) - kd * dq
for _ in range(20):
    mujoco.mj_step(model, data)

# 正确: 每步都算 PD
for _ in range(decimation):
    q = data.qpos[dof_ids]; dq = data.qvel[dof_vel]
    tau = kp * (target - q) - kd * dq
    data.ctrl[:] = tau
    mujoco.mj_step(model, data)
```

---

## Bug 5: 站立阶段 last_action 清零

**现象**: 站立→行走切换时策略输出异常。

**根因**: Python 仿真脚本在站立阶段把 `last_action` 设为全零，训练时站立阶段也保存策略输出。

```python
# 错误
if walking: last_action = raw_action.copy()
else: last_action = np.zeros(16)  # 全零

# 正确（和参考代码一致）
last_action = action.copy()  # 不管站不站立，都保存
```

---

## Bug 6: History 偏移 1 帧

**现象**: 策略看到的时间窗口比训练时短 1 帧。

**根因**: Dart Walk.doing() 拼接 history 时 `i=1` 开始，跳过了最老帧。

```dart
// 错误: 从 i=1 开始
for (int i = 1; i < historySize; i++) { ... }
// 正确: 从 i=0 开始
for (int i = 0; i < historySize - 1; i++) { ... }
```

---

## Bug 7: 四元数取共轭导致 projectedGravity 反向

**现象**: 仿真中 `grav_y` 符号与训练相反。

**根因**: Python 仿真脚本对 MuJoCo sensor 四元数取了共轭后再传给 Dart。但 Dart 的 `q.rotate([0,0,-1])` 用原始四元数就是正确的。

```python
# 错误: 取共轭
qx, qy, qz = -raw[1], -raw[2], -raw[3]
# 正确: 直接透传
qx, qy, qz = raw[1], raw[2], raw[3]
```

---

## Bug 8: gRPC 异常导致客户端崩溃

**现象**: 手柄控制时 Walk 发太快/状态不对 → 客户端直接崩溃。

**根因**: 服务端对不合法命令抛 `GrpcError` 异常（RESOURCE_EXHAUSTED / FAILED_PRECONDITION），客户端没容错。

**修复**: 服务端所有运动指令在不合适状态下**静默返回 Empty**，不抛异常。真机上等同于"按了没反应"，不会炸机。

---

## Bug 9: Transition error+done 竞态

**现象**: 过渡流 error 后 stale Done 完成了替换的过渡。

**根因**: `_listenTransition` 的 `onError` 触发 Fault → 新 Transitioning → 旧流的 `onDone` 触发 Done → 误完成新过渡。

**修复**: `onError` 里调 `sub.cancel()` 阻止后续 `onDone`，加 `faulted` 标志双重保护。

---

## 核心教训

**RL 策略对 obs 约定极度敏感。** 初始化值、缩放、符号、clamp、history 顺序——任何一个和训练时不一致，策略就输出错误动作。"物理上更正确"不等于"策略能用"——策略只认训练时看到的数据分布。

## 正确的仿真循环模板

```python
model.opt.timestep = 0.005
decimation = 4  # 推理 50Hz, PD 200Hz

for i in range(total_steps):
    if count % decimation == 0:
        obs = get_obs(data, cmd, last_action)
        obs_history.append(obs)
        raw_action = onnx_run(obs_history)

        if count > warmup:
            target_q = raw_action * action_scale + default_angle
        else:
            target_q = default_angle
        last_action = raw_action.copy()  # 始终保存！

    # PD 每步都算
    q = data.qpos[dof_ids]; dq = data.qvel[dof_vel]
    tau[:12] = kp * (target[:12] - q[:12]) - kd * dq[:12]
    tau[12:] = wheel_kd * (target[12:] - dq[12:])
    data.ctrl[:] = np.clip(tau, -100, 100)
    mujoco.mj_step(model, data)
    count += 1
```
