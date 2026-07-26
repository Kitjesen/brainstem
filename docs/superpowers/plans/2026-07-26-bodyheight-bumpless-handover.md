# H15/H18 策略零点与无冲击接管 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留机器人端已经验证的 Body-height 遥控模式，将 H15/H18 的物理站姿与策略训练零点分离，并在云卓遥控器触发 Standing → Walking 时用 100 个实际下发间隔完成 2 秒无冲击接管。

**Architecture:** `RobotProfile` 明确提供 `standUpPose` 和 `policyDefaultPose`，旧 `standingPose` 同时作为两者的兼容回退。新增纯 Dart `BodyHeightHandover` 保存 requested/running/suspended 状态并计算 action/Kp/Kd 的 smoothstep 帧；`RealControlDog` 负责请求、取消和重启接管，`han_dog.dart` 只在电机输出门已经打开且即将调用 `sendAction` 时推进帧号。

**Tech Stack:** Dart 3.12、`test`/`mocktail`/`fake_async`、ONNX Runtime、现有 CMS/ControlArbiter、Python 3 MuJoCo 离线验证。

---

## 实施约束与现状

- 已批准规格：
  `docs/superpowers/specs/2026-07-26-bodyheight-bumpless-handover-design.md`。
- 本地执行目录：
  `E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\brainstem-bodyheightctrl`。
- 本地 Dart：
  `E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe`。
- 机器人目录：`/home/bsrl1/brainstem-bodyheightctrl`。
- 机器人端已有但尚未回收到 Git 的 Body-height 遥控改动位于
  `real_control_dog.dart`、`profile_manager.dart`、`han_dog.dart`、H15/H18
  profiles 及相应测试；实现必须保留这些行为。
- 机器人端 `real_controller.dart`、`monitoring.dart`、`robo_device*` 还有与
  本功能无关的工作区改动。本计划不覆盖、不提交这些文件。
- 本地 `real_controller.dart`、`controller_test.dart` 及 diagnostics 文件也有
  独立未提交工作。本计划不把它们加入任何提交。
- 所有提交使用单次命令身份：
  `git -c user.name=hahadahe -c user.email=911987281@qq.com commit ...`；
  不修改仓库默认 Git 配置。
- 自动化过程不得启动/停止 `han_dog.service` 或
  `han-dog-bodyheight.service`，不得调用电机 Enable、StandUp、Walk、
  SetBodyHeight 等实机 RPC。

## 文件边界

### 新建

- `han_dog/lib/src/body_height_handover.dart`：纯状态机与 smoothstep
  action/Kp/Kd 插值，不访问硬件。
- `han_dog/lib/src/motor_action_dispatcher.dart`：把 output-enable、Grounded
  hold、motor-health gate、send 和 `markApplied()` 固定为可测试顺序。
- `han_dog/test/body_height_handover_test.dart`：100 个实际下发间隔、暂停、
  重启、取消和采集首帧回归。
- `han_dog/test/motor_action_dispatcher_test.dart`：证明只有成功完成真实输出
  回调才推进 handover。
- `han_dog/test/body_height_profile_contract_test.dart`：H15/H18 JSON 的安全
  站姿、训练零点、0.40 m 和维度契约。

### 修改

- `han_dog/lib/src/app/robot_profile.dart`：解析并分流两种姿态。
- `han_dog/lib/src/app/profile_manager.dart`：Brain/Gesture 使用物理站姿，
  保留机器人端禁止 Body-height 热切换的规则。
- `han_dog_brain/lib/src/brain.dart`：`StandUp` 不再从 observation builder
  获取策略零点。
- `han_dog_brain/test/behaviour_test.dart`：锁定 Brain 的两种姿态语义。
- `han_dog/test/han_dog_test.dart`：旧 profile 双回退和新字段校验。
- `han_dog/test/profile_manager_test.dart`：切换时两种姿态路由正确。
- `han_dog/lib/src/real_control_dog.dart`：回收机器人端 Body-height 模式并接入
  handover 生命周期。
- `han_dog/test/real_control_dog_test.dart`：遥控命令冻结、中断、断使能重启。
- `han_dog/bin/han_dog.dart`：创建共享 handover，并在真实输出边界应用它。
- `han_dog/bin/server.dart`：仿真 Brain 使用 `standUpPose`。
- `han_dog/lib/han_dog.dart`：导出 handover 类型。
- `han_dog/profiles/thunder_h15.json`、`thunder_h18.json`：安全站姿、训练零点、
  默认 0.40 m。
- `docs/BODYHEIGHTCTRL.md`、根 `README.md`：记录姿态字段、命令范围、2 秒
  接管和 R2 的 Body-height 重启限制。

## Task 1: 将机器人端现有 Body-height 遥控模式回收到本地基线

**Files:**

- Modify: `han_dog/test/real_control_dog_test.dart`
- Modify: `han_dog/test/profile_manager_test.dart`
- Modify: `han_dog/lib/src/real_control_dog.dart`
- Modify: `han_dog/lib/src/app/profile_manager.dart`
- Modify: `han_dog/bin/han_dog.dart`

- [ ] **Step 1: 先加入当前机器人行为的回归测试**

在 `real_control_dog_test.dart` 增加 `bodyHeightCtrl` broadcast controller，
将 `controller.bodyHeightAxis` stub 到该 stream，并在 `tearDown()` 关闭。
`buildDog({RobotProfile? initialProfile})` 把参数传给 `RealControlDog`；
`bodyHeightProfile()` 使用 `observationType: 'bodyHeight'`、默认 0.40 和范围
0.20–0.54。然后增加以下独立用例：

```dart
test('body-height axis enters Walking with zero velocity', () {
  fakeAsync((async) {
    when(() => arbiter.state).thenReturn(
      Standing(Stream<History>.empty().listen((_) {})),
    );
    final dog = buildDog(initialProfile: bodyHeightProfile());

    bodyHeightCtrl.add(1.0);
    async.flushMicrotasks();

    final command = verify(
      () => arbiter.command(
        captureAny(that: isA<CmdWalk>()),
        ControlSource.yunzhuo,
      ),
    ).captured.single as CmdWalk;
    expect(command.direction, Vector3.zero());
    dog.dispose();
  });
});

test('body-height R1 resets the profile default while Standing', () {
  fakeAsync((async) {
    when(() => arbiter.state).thenReturn(
      Standing(Stream<History>.empty().listen((_) {})),
    );
    final dog = buildDog(initialProfile: bodyHeightProfile());

    idleCtrl.add(true);
    async.flushMicrotasks();

    final command = verify(
      () => arbiter.command(
        captureAny(that: isA<CmdSetBodyHeight>()),
        ControlSource.yunzhuo,
      ),
    ).captured.single as CmdSetBodyHeight;
    expect(command.meters, 0.40);
    dog.dispose();
  });
});

test('body-height R2 requires a service restart', () {
  fakeAsync((async) {
    when(() => arbiter.state).thenReturn(
      Standing(Stream<History>.empty().listen((_) {})),
    );
    final dog = buildDog(initialProfile: bodyHeightProfile());
    var switched = false;
    dog.onProfileSwitch = () => switched = true;

    switchProfileCtrl.add(null);
    async.flushMicrotasks();

    expect(switched, isFalse);
    dog.dispose();
  });
});

test('full body-height input advances exactly 0.0004 m per 20 ms', () {
  fakeAsync((async) {
    when(() => arbiter.state).thenReturn(
      Walking(Stream<History>.empty().listen((_) {})),
    );
    final dog = buildDog(initialProfile: bodyHeightProfile());

    bodyHeightCtrl.add(1.0);
    async.elapse(const Duration(milliseconds: 20));

    final command = verify(
      () => arbiter.command(
        captureAny(that: isA<CmdSetBodyHeight>()),
        ControlSource.yunzhuo,
      ),
    ).captured.single as CmdSetBodyHeight;
    expect(command.meters, closeTo(0.4004, 1e-12));
    dog.dispose();
  });
});

test('standard profile never subscribes to body-height axis', () {
  final dog = buildDog();

  verifyNever(() => controller.bodyHeightAxis);
  dog.dispose();
});
```

在 `profile_manager_test.dart` 的 `_profile` helper 增加可选
`String observationType = 'standard'` 并传给 `RobotProfile`，然后增加：

```dart
test('runtime switch involving a body-height profile requires restart', () async {
  profiles['h15'] = _profile(
    'h15',
    _pose2,
    _kp2,
    _kd2,
    observationType: 'bodyHeight',
  );
  final manager = ProfileManager(
    profiles: profiles,
    brain: brain,
    initial: 'alpha',
  );

  await expectLater(manager.switchTo('h15'), throwsStateError);
  expect(manager.currentName, 'alpha');
});

test('R2 toggle excludes body-height profiles', () async {
  profiles = {
    'alpha': profiles['alpha']!,
    'h15': _profile(
      'h15',
      _pose1,
      _kp1,
      _kd1,
      observationType: 'bodyHeight',
    ),
    'beta': profiles['beta']!,
  };
  final manager = ProfileManager(
    profiles: profiles,
    brain: brain,
    initial: 'alpha',
  );

  await manager.toggle();

  expect(manager.currentName, 'beta');
});
```

- [ ] **Step 2: 运行测试，确认 RED**

Run:

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog/test/real_control_dog_test.dart han_dog/test/profile_manager_test.dart --reporter expanded
```

Expected: FAIL，原因分别是 `RealControlDog` 不接受 `initialProfile`、不订阅
`bodyHeightAxis`，且 `ProfileManager` 仍允许 Body-height 热切换。

- [ ] **Step 3: 回收最小生产实现**

从机器人当前工作区行为回收以下契约，不复制机器人端其他文件：

```dart
static const _bodyHeightDeadzone = 0.10;
static const _bodyHeightRateMetersPerSecond = 0.02;
static const _bodyHeightTick = Duration(milliseconds: 20);
```

`RealControlDog` 构造器增加 `RobotProfile? initialProfile`，仅当
`initialProfile.observationType == 'bodyHeight'` 时：

- 校验默认值及 `[min, max]`；
- 要求 controller 实现 `BodyHeightAxisInput`；
- 订阅右摇杆 Y；
- 以 50 Hz、0.02 m/s、0.10 死区积分；
- R1 在 Standing 重置到 profile 默认值；
- R2 记录“需重启服务”并拒绝热切换；
- standard profile 不读取体高轴；
- `dispose()` 释放 Timer 和订阅。

`ProfileManager.switchTo()` 在当前或目标 profile 为 Body-height 时抛出：

```dart
throw StateError('Body-height profile changes require a service restart');
```

`toggle()` 只遍历 `observationType != 'bodyHeight'` 的 profile。
`han_dog.dart` 的两个 `RealControlDog` 创建点都传入
`initialProfile: defaultProfile`。

- [ ] **Step 4: 运行测试，确认 GREEN**

Run Task 1 Step 2 的同一命令。

Expected: 两个测试文件全部 PASS，且没有访问串口、CAN 或 ONNX。

- [ ] **Step 5: 提交遥控模式基线**

```powershell
git add -- han_dog/lib/src/real_control_dog.dart han_dog/lib/src/app/profile_manager.dart han_dog/bin/han_dog.dart han_dog/test/real_control_dog_test.dart han_dog/test/profile_manager_test.dart
$expected = @(
  'han_dog/bin/han_dog.dart'
  'han_dog/lib/src/app/profile_manager.dart'
  'han_dog/lib/src/real_control_dog.dart'
  'han_dog/test/profile_manager_test.dart'
  'han_dog/test/real_control_dog_test.dart'
) | Sort-Object
$actual = @(git diff --cached --name-only) | Sort-Object
if (@(Compare-Object $expected $actual).Count -ne 0) {
  throw "staged files differ from Task 1 allowlist`n$($actual -join "`n")"
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Task 1 staged diff check failed' }
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(bodyheight): preserve profile-aware remote mode"
if ($LASTEXITCODE -ne 0) { throw 'Task 1 commit failed' }
```

## Task 2: 为 Profile 增加物理站姿与策略零点契约

**Files:**

- Modify: `han_dog/test/han_dog_test.dart`
- Modify: `han_dog/lib/src/app/robot_profile.dart`

- [ ] **Step 1: 写 legacy 回退、显式分流和错误输入测试**

在 `RobotProfile.fromJson` group 增加：

```dart
test('legacy standingPose feeds both explicit pose roles', () {
  final profile = RobotProfile.fromJson(validJson());

  expect(profile.standUpPose.values, profile.standingPose.values);
  expect(profile.policyDefaultPose.values, profile.standingPose.values);
});

test('explicit stand and policy poses remain independent', () {
  final json = validJson()
    ..['standUpPose'] = List<num>.generate(16, (index) => index / 10)
    ..['policyDefaultPose'] = List<num>.generate(16, (index) => -index / 10);

  final profile = RobotProfile.fromJson(json);

  expect(profile.standUpPose.values[5], 0.5);
  expect(profile.policyDefaultPose.values[5], -0.5);
  expect(
    profile.toObservationBuilder().standingPose.values,
    profile.policyDefaultPose.values,
  );
});

for (final field in ['standUpPose', 'policyDefaultPose']) {
  test('$field requires exactly 16 finite numeric values', () {
    final short = validJson()..[field] = List<num>.filled(15, 0);
    final nonFinite = validJson()..[field] = List<num>.filled(16, double.nan);

    expect(() => RobotProfile.fromJson(short), throwsFormatException);
    expect(() => RobotProfile.fromJson(nonFinite), throwsFormatException);
  });
}
```

- [ ] **Step 2: 运行测试，确认 RED**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog/test/han_dog_test.dart --reporter expanded
```

Expected: compile FAIL，`RobotProfile` 尚无 `standUpPose` 和
`policyDefaultPose`。

- [ ] **Step 3: 实现双字段和兼容回退**

在 `RobotProfile` 中使用以下构造语义：

```dart
final JointsMatrix standingPose;
final JointsMatrix standUpPose;
final JointsMatrix policyDefaultPose;

const RobotProfile({
  required this.name,
  this.description = '',
  required this.modelPath,
  this.inputName,
  required this.standingPose,
  JointsMatrix? standUpPose,
  JointsMatrix? policyDefaultPose,
  required this.sittingPose,
  this.standUpCounts = 150,
  this.sitDownCounts = 150,
  required this.inferKp,
  required this.inferKd,
  required this.standUpKp,
  required this.standUpKd,
  required this.sitDownKp,
  required this.sitDownKd,
  this.imuGyroscopeScale = 0.25,
  this.jointVelocityScale = (0.05, 0.05, 0.05, 0.05),
  this.actionScale = (0.125, 0.25, 0.25, 5.0),
  this.observationType = 'standard',
  this.bodyHeightCommand = 0.35,
  this.minBodyHeightCommand = 0.20,
  this.maxBodyHeightCommand = 0.54,
  this.velocityCommandMin = (-3.0, -3.0, -3.0),
  this.velocityCommandMax = (3.0, 3.0, 3.0),
}) : standUpPose = standUpPose ?? standingPose,
     policyDefaultPose = policyDefaultPose ?? standingPose;
```

`fromJson()` 先解析一次 legacy pose，再解析两个可选字段：

```dart
final standingPose = _joints16(json, 'standingPose');
final standUpPose = json.containsKey('standUpPose')
    ? _joints16(json, 'standUpPose')
    : standingPose;
final policyDefaultPose = json.containsKey('policyDefaultPose')
    ? _joints16(json, 'policyDefaultPose')
    : standingPose;
```

构造 `RobotProfile` 时传入三者；`toObservationBuilder()` 的 standard 和
bodyHeight 分支都使用 `policyDefaultPose`。

- [ ] **Step 4: 运行测试，确认 GREEN**

Run Task 2 Step 2 的同一命令。

Expected: `han_dog_test.dart` 全部 PASS。

- [ ] **Step 5: 提交 Profile 契约**

```powershell
git add -- han_dog/lib/src/app/robot_profile.dart han_dog/test/han_dog_test.dart
$expected = @(
  'han_dog/lib/src/app/robot_profile.dart'
  'han_dog/test/han_dog_test.dart'
) | Sort-Object
$actual = @(git diff --cached --name-only) | Sort-Object
if (@(Compare-Object $expected $actual).Count -ne 0) {
  throw "staged files differ from Task 2 allowlist`n$($actual -join "`n")"
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Task 2 staged diff check failed' }
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(bodyheight): split stand and policy poses"
if ($LASTEXITCODE -ne 0) { throw 'Task 2 commit failed' }
```

## Task 3: 切断 Brain 中 StandUp 与策略零点的隐式耦合

**Files:**

- Modify: `han_dog_brain/test/behaviour_test.dart`
- Modify: `han_dog_brain/lib/src/brain.dart`
- Modify: `han_dog/lib/src/app/profile_manager.dart`
- Modify: `han_dog/test/profile_manager_test.dart`
- Modify: `han_dog/bin/han_dog.dart`
- Modify: `han_dog/bin/server.dart`

- [ ] **Step 1: 写 Brain 双姿态测试**

在 `behaviour_test.dart` 增加：

```dart
test('Brain keeps physical stand pose separate from policy default pose', () {
  final physicalStand = JointsMatrix.fromList(List<double>.filled(16, 0.4));
  final policyDefault = JointsMatrix.fromList(List<double>.filled(16, -0.7));
  final brain = Brain(
    imu: imu,
    joint: joint,
    clock: clock,
    standingPose: physicalStand,
    sittingPose: JointsMatrix.zero(),
    observationBuilder: BodyHeightObservationBuilder(
      standingPose: policyDefault,
    ),
  );
  addTearDown(brain.dispose);

  expect(brain.standUp.standingPose.values, physicalStand.values);
  expect(brain.walk.observationBuilder.standingPose.values, policyDefault.values);
  expect(brain.standingPose.values, physicalStand.values);
});
```

在 `profile_manager_test.dart` 的 successful switch 用例中，构造
`standUpPose != policyDefaultPose` 的 profile，并验证：

```dart
final call = verify(
  () => brain.switchProfile(
    observationBuilder: captureAny(named: 'observationBuilder'),
    standingPose: captureAny(named: 'standingPose'),
    sittingPose: any(named: 'sittingPose'),
    modelPath: any(named: 'modelPath'),
    standUpCounts: any(named: 'standUpCounts'),
    sitDownCounts: any(named: 'sitDownCounts'),
    inputName: any(named: 'inputName'),
    bodyHeightCommand: any(named: 'bodyHeightCommand'),
    minBodyHeightCommand: any(named: 'minBodyHeightCommand'),
    maxBodyHeightCommand: any(named: 'maxBodyHeightCommand'),
  ),
).captured;
expect((call[0] as ObservationBuilder).standingPose.values, policyPose.values);
expect((call[1] as JointsMatrix).values, standPose.values);
```

- [ ] **Step 2: 运行测试，确认 RED**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog_brain/test/behaviour_test.dart han_dog/test/profile_manager_test.dart --reporter expanded
```

Expected: Brain 测试 FAIL，因为 `Brain.shareMemory` 仍把 builder 的
`standingPose` 传给 `StandUp`；ProfileManager 测试 FAIL，因为仍传 legacy
字段。

- [ ] **Step 3: 最小修改 Brain 和调用方**

`Brain.shareMemory` 增加：

```dart
required JointsMatrix standingPose,
```

并让 `StandUp` 使用该参数：

```dart
standUp = StandUp(
  clock: clock,
  imu: imu,
  joint: joint,
  memory: memory,
  bodyHeightCommandProvider: bodyHeightCommandProvider,
  standingPose: standingPose,
  counts: standUpCounts,
),
```

`Brain` factory 调用 `Brain.shareMemory` 时传入 factory 的
`standingPose`。兼容 getter 改成：

```dart
JointsMatrix get standingPose => standUp.standingPose;
```

`ProfileManager` 的 `Brain.switchProfile(standingPose:)` 和
`GestureLibrary(standingPose:)` 均改用 `p.standUpPose`；回滚路径均使用
`prevProfile.standUpPose`。`han_dog.dart` 和 `server.dart` 创建 Brain 时使用
`defaultProfile.standUpPose`，但 observation builder 保持
`defaultProfile.toObservationBuilder()`。`server.dart` 的
`SimSensorService(standingPose:)` 也代表仿真初始实测姿态，必须使用
`defaultProfile.standUpPose`，不能使用策略零点。

- [ ] **Step 4: 运行测试，确认 GREEN**

Run Task 3 Step 2 的同一命令。

Expected: 两个测试文件全部 PASS。

- [ ] **Step 5: 提交 Brain 路由**

```powershell
git add -- han_dog_brain/lib/src/brain.dart han_dog_brain/test/behaviour_test.dart han_dog/lib/src/app/profile_manager.dart han_dog/test/profile_manager_test.dart han_dog/bin/han_dog.dart han_dog/bin/server.dart
$expected = @(
  'han_dog/bin/han_dog.dart'
  'han_dog/bin/server.dart'
  'han_dog/lib/src/app/profile_manager.dart'
  'han_dog/test/profile_manager_test.dart'
  'han_dog_brain/lib/src/brain.dart'
  'han_dog_brain/test/behaviour_test.dart'
) | Sort-Object
$actual = @(git diff --cached --name-only) | Sort-Object
if (@(Compare-Object $expected $actual).Count -ne 0) {
  throw "staged files differ from Task 3 allowlist`n$($actual -join "`n")"
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Task 3 staged diff check failed' }
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "fix(bodyheight): route physical and policy poses separately"
if ($LASTEXITCODE -ne 0) { throw 'Task 3 commit failed' }
```

## Task 4: 固化 H15/H18 最终 Profile 契约

**Files:**

- Create: `han_dog/test/body_height_profile_contract_test.dart`
- Modify: `han_dog/profiles/thunder_h15.json`
- Modify: `han_dog/profiles/thunder_h18.json`

- [ ] **Step 1: 写 profile 文件级测试**

创建测试，分别对 H15/H18 断言：

```dart
const safeStandPose = <double>[
  -0.1, -0.8, 1.8,
   0.1,  0.8, -1.8,
   0.1,  0.8, -1.8,
  -0.1, -0.8, 1.8,
   0.0,  0.0, 0.0, 0.0,
];

const trainedPolicyPose = <double>[
  -0.1, -1.1, 2.6,
   0.1,  1.1, -2.6,
   0.1,  1.1, -2.6,
  -0.1, -1.1, 2.6,
   0.0,  0.0, 0.0, 0.0,
];
```

每个 profile 的测试体：

```dart
final raw = _loadProfile(name);
final parsed = RobotProfile.fromJson(raw);

expect(_doubleList(raw['standingPose']), safeStandPose);
expect(_doubleList(raw['standUpPose']), safeStandPose);
expect(_doubleList(raw['policyDefaultPose']), trainedPolicyPose);
expect(parsed.standUpPose.values, safeStandPose);
expect(parsed.policyDefaultPose.values, trainedPolicyPose);
expect(parsed.toObservationBuilder().standingPose.values, trainedPolicyPose);
expect(parsed.bodyHeightCommand, 0.40);
expect(parsed.minBodyHeightCommand, 0.20);
expect(parsed.maxBodyHeightCommand, 0.54);
expect(parsed.toObservationBuilder().tensorSize, 58);
```

H15/H18 的历史维度继续由模型 smoke test 分别验证为 58/580；JSON 测试不把
`_historySize` 误当作 observation builder 的单帧维度。

- [ ] **Step 2: 运行测试，确认 RED**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog/test/body_height_profile_contract_test.dart --reporter expanded
```

Expected: FAIL，当前 profiles 缺少两个显式字段且默认体高不是 0.40。

- [ ] **Step 3: 修改 H15/H18 JSON**

两个文件都写入：

```json
"bodyHeightCommand": 0.4,
"standingPose": [-0.1, -0.8, 1.8, 0.1, 0.8, -1.8, 0.1, 0.8, -1.8, -0.1, -0.8, 1.8, 0, 0, 0, 0],
"standUpPose": [-0.1, -0.8, 1.8, 0.1, 0.8, -1.8, 0.1, 0.8, -1.8, -0.1, -0.8, 1.8, 0, 0, 0, 0],
"policyDefaultPose": [-0.1, -1.1, 2.6, 0.1, 1.1, -2.6, 0.1, 1.1, -2.6, -0.1, -1.1, 2.6, 0, 0, 0, 0]
```

模型路径、inputName、hash、增益、速度范围、0.20–0.54 m 范围和 action
scale 不变。

- [ ] **Step 4: 运行测试，确认 GREEN**

Run Task 4 Step 2 的同一命令。

Expected: H15/H18 全部契约测试 PASS。

- [ ] **Step 5: 提交 profiles**

```powershell
git add -- han_dog/profiles/thunder_h15.json han_dog/profiles/thunder_h18.json han_dog/test/body_height_profile_contract_test.dart
$expected = @(
  'han_dog/profiles/thunder_h15.json'
  'han_dog/profiles/thunder_h18.json'
  'han_dog/test/body_height_profile_contract_test.dart'
) | Sort-Object
$actual = @(git diff --cached --name-only) | Sort-Object
if (@(Compare-Object $expected $actual).Count -ne 0) {
  throw "staged files differ from Task 4 allowlist`n$($actual -join "`n")"
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Task 4 staged diff check failed' }
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "fix(bodyheight): restore trained policy zero"
if ($LASTEXITCODE -ne 0) { throw 'Task 4 commit failed' }
```

## Task 5: 用纯状态对象实现 100 间隔 smoothstep

**Files:**

- Create: `han_dog/test/body_height_handover_test.dart`
- Create: `han_dog/lib/src/body_height_handover.dart`
- Modify: `han_dog/lib/han_dog.dart`

- [ ] **Step 1: 写纯单元测试**

测试必须覆盖：

```dart
test('frame 0, 50, and 100 share one smoothstep for action and gains', () {
  final handover = buildHandover();
  handover.requestFrom(startAction);
  handover.begin();

  final frame0 = handover.preview(policyAction);
  expect(frame0.frameIndex, 0);
  expect(frame0.alpha, 0.0);
  expect(frame0.action.values, startAction.discardFoot().values);
  expect(frame0.kp.values, standKp.values);
  expect(frame0.kd.values, standKd.values);

  for (var index = 0; index < 50; index++) {
    handover.markApplied();
  }
  final frame50 = handover.preview(policyAction);
  expect(frame50.frameIndex, 50);
  expect(frame50.alpha, closeTo(0.5, 1e-12));
  expect(frame50.action.values[12], closeTo(policyAction.values[12] * 0.5, 1e-12));

  for (var index = 50; index < 100; index++) {
    handover.markApplied();
  }
  final frame100 = handover.preview(policyAction);
  expect(frame100.frameIndex, 100);
  expect(frame100.alpha, 1.0);
  expect(frame100.action.values, policyAction.values);
  expect(frame100.kp.values, inferKp.values);
  expect(frame100.kd.values, inferKd.values);

  handover.markApplied();
  expect(handover.blocksControllerCommands, isFalse);
});

test('preview without an applied send never advances', () {
  final handover = buildHandover()
    ..requestFrom(startAction)
    ..begin();

  expect(handover.preview(policyAction).frameIndex, 0);
  expect(handover.preview(policyAction).frameIndex, 0);
});

test('disable suspends and re-enable restarts at a fresh measured pose', () {
  final handover = buildHandover()
    ..requestFrom(startAction)
    ..begin();
  handover.markApplied();
  handover.suspend();

  expect(handover.isSuspended, isTrue);
  final fresh = JointsMatrix.fromList(List<double>.filled(16, 0.25));
  handover.restartFrom(fresh);
  final restarted = handover.preview(policyAction);

  expect(restarted.frameIndex, 0);
  expect(restarted.action.values, fresh.discardFoot().values);
});

test('request captures qStart before Walking is confirmed', () {
  final handover = buildHandover();
  handover.requestFrom(startAction);

  final laterMeasurement = JointsMatrix.fromList(
    List<double>.filled(16, 0.75),
  );
  handover.begin();
  final frame0 = handover.preview(policyAction);

  expect(frame0.action.values, startAction.discardFoot().values);
  expect(frame0.action.values, isNot(laterMeasurement.discardFoot().values));
});

test('disable can suspend a request before Walking confirmation', () {
  final handover = buildHandover();
  handover.requestFrom(startAction);

  handover.suspend();

  expect(handover.isSuspended, isTrue);
  expect(handover.blocksControllerCommands, isTrue);
});
```

加入采集首帧回归，使用 CSV 第 280 行的 12 个腿关节 `qStart` 和修正策略
目标 `qPolicy`：

```dart
const qStartLegs = <double>[
  -0.007864, -0.838384, 1.718005,
   0.009015,  0.838000, -1.699976,
   0.016304,  0.833397, -1.712635,
  -0.016687, -0.839151, 1.716855,
];
const qPolicyLegs = <double>[
   0.045852, -0.674532, 1.654495,
   0.101351,  0.842166, -1.876151,
  -0.138215,  0.859309, -1.745764,
  -0.079694, -0.971636, 1.921697,
];
```

断言 frame 0 相对 `qStart` 的最大跳变为 0，并且 frame 100 的策略目标最大
差值不超过 `0.25 rad`。

- [ ] **Step 2: 运行测试，确认 RED**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog/test/body_height_handover_test.dart --reporter expanded
```

Expected: compile FAIL，`BodyHeightHandover` 尚不存在。

- [ ] **Step 3: 实现最小纯状态机**

生产接口固定为：

```dart
final class BodyHeightHandoverFrame {
  final int frameIndex;
  final double alpha;
  final JointsMatrix action;
  final JointsMatrix kp;
  final JointsMatrix kd;

  const BodyHeightHandoverFrame({
    required this.frameIndex,
    required this.alpha,
    required this.action,
    required this.kp,
    required this.kd,
  });
}

final class BodyHeightHandover {
  static const intervalCount = 100;

  final JointsMatrix standUpKp;
  final JointsMatrix standUpKd;
  final JointsMatrix inferKp;
  final JointsMatrix inferKd;

  int _frameIndex = 0;
  JointsMatrix? _startAction;
  _BodyHeightHandoverPhase _phase = _BodyHeightHandoverPhase.idle;

  BodyHeightHandover({
    required this.standUpKp,
    required this.standUpKd,
    required this.inferKp,
    required this.inferKd,
  });

  bool get isRequested => _phase == _BodyHeightHandoverPhase.requested;
  bool get isRunning => _phase == _BodyHeightHandoverPhase.running;
  bool get isSuspended => _phase == _BodyHeightHandoverPhase.suspended;
  bool get blocksControllerCommands => _phase != _BodyHeightHandoverPhase.idle;

  void requestFrom(JointsMatrix measuredPosition) {
    _phase = _BodyHeightHandoverPhase.requested;
    _frameIndex = 0;
    _startAction = measuredPosition.discardFoot();
  }

  void begin() {
    if (!isRequested) {
      throw StateError('Body-height handover was not requested');
    }
    _frameIndex = 0;
    _phase = _BodyHeightHandoverPhase.running;
  }

  void suspend() {
    if (isRequested || isRunning) {
      _phase = _BodyHeightHandoverPhase.suspended;
    }
  }

  void restartFrom(JointsMatrix measuredPosition) {
    if (!isSuspended) {
      throw StateError('Body-height handover is not suspended');
    }
    _startAction = measuredPosition.discardFoot();
    _frameIndex = 0;
    _phase = _BodyHeightHandoverPhase.running;
  }

  void cancel() {
    _phase = _BodyHeightHandoverPhase.idle;
    _frameIndex = 0;
    _startAction = null;
  }

  BodyHeightHandoverFrame preview(JointsMatrix policyAction) {
    final startAction = _startAction;
    if (!isRunning || startAction == null) {
      throw StateError('Body-height handover is not running');
    }
    final s = (_frameIndex / intervalCount).clamp(0.0, 1.0).toDouble();
    final alpha = s * s * (3.0 - 2.0 * s);
    return BodyHeightHandoverFrame(
      frameIndex: _frameIndex,
      alpha: alpha,
      action: JointsMatrix.lerp(startAction, policyAction, alpha),
      kp: JointsMatrix.lerp(standUpKp, inferKp, alpha),
      kd: JointsMatrix.lerp(standUpKd, inferKd, alpha),
    );
  }

  void markApplied() {
    if (!isRunning) {
      throw StateError('Body-height handover is not running');
    }
    if (_frameIndex == intervalCount) {
      cancel();
      return;
    }
    _frameIndex++;
  }
}

enum _BodyHeightHandoverPhase { idle, requested, running, suspended }
```

在 `han_dog/lib/han_dog.dart` 导出该文件。

- [ ] **Step 4: 运行测试，确认 GREEN**

Run Task 5 Step 2 的同一命令。

Expected: 全部纯测试 PASS；frame 0 和 frame 100 共 101 次 send sample，形成
恰好 100 个实际控制间隔。

- [ ] **Step 5: 提交纯 handover**

```powershell
git add -- han_dog/lib/src/body_height_handover.dart han_dog/lib/han_dog.dart han_dog/test/body_height_handover_test.dart
$expected = @(
  'han_dog/lib/han_dog.dart'
  'han_dog/lib/src/body_height_handover.dart'
  'han_dog/test/body_height_handover_test.dart'
) | Sort-Object
$actual = @(git diff --cached --name-only) | Sort-Object
if (@(Compare-Object $expected $actual).Count -ne 0) {
  throw "staged files differ from Task 5 allowlist`n$($actual -join "`n")"
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Task 5 staged diff check failed' }
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(bodyheight): add bumpless handover state"
if ($LASTEXITCODE -ne 0) { throw 'Task 5 commit failed' }
```

## Task 6: 将 handover 接入遥控 FSM 与真实输出边界

**Files:**

- Modify: `han_dog/test/real_control_dog_test.dart`
- Modify: `han_dog/lib/src/real_control_dog.dart`
- Create: `han_dog/test/motor_action_dispatcher_test.dart`
- Create: `han_dog/lib/src/motor_action_dispatcher.dart`
- Modify: `han_dog/lib/han_dog.dart`
- Modify: `han_dog/bin/han_dog.dart`

- [ ] **Step 1: 写遥控生命周期失败测试**

向 `buildDog` 注入同一个 `BodyHeightHandover`，增加以下行为测试：

- Standing 中左摇杆非零只发送 `Walk(Vector3.zero())` 并进入 requested；
- Standing 中右摇杆非零执行相同请求；
- 请求时立即从 `joint.position` 采样；Walking 确认前改变反馈值也不能改变
  frame 0 的起点；
- requested/running/suspended 期间后续方向和体高输入不发送；
- stateStream 确认 Walking 时只把 requested 切换为 running；
- L1、L2、R1 在发送现有 FSM 命令前取消；
- Grounded、Zero、意外 Transitioning、故障以及 Walking 离开时取消；
- H=false 和红键立即 suspend 并令输出门 false；
- request 尚未收到 Walking 确认时，H=false/红键也必须进入 suspended；
- H=true 且仍为 Walking 时从新的 `joint.position` 重启 frame 0；
- handover 完成后，新的左摇杆速度和右摇杆体高输入恢复；
- 接管完成后若没有新的右摇杆事件，不得使用接管前保存的轴值继续调高；
- handover 期间 `brain.bodyHeightCommand` 保持 profile 默认 `0.40`。

状态流测试按以下矩阵逐项覆盖，避免把“等待 Walking 确认的 Standing”误判为
离开 Walking：

| Handover phase | 收到 Standing | 收到 Walking | 收到 Grounded/Zero/Transitioning/Fault |
|---|---|---|---|
| idle | 保持 idle | 保持 idle | 保持 idle |
| requested | 保留请求并等待确认 | `begin()` | `cancel()` |
| running | `cancel()` | 保持 running | `cancel()` |
| suspended | `cancel()` | 保持 suspended，等待重新使能 | `cancel()` |

state stream 的 `onError` 先 `cancel()`，再进入既有 fault 路径；L1/L2/R1
在发出 FSM 命令前已经 `cancel()`，因此随后出现的 Standing/Transitioning
事件不会重新激活接管。

核心断言使用：

```dart
expect(handover.isRequested, isTrue);
expect(handover.blocksControllerCommands, isTrue);
verify(
  () => arbiter.command(
    any(that: isA<CmdWalk>().having(
      (command) => command.direction,
      'direction',
      Vector3.zero(),
    )),
    ControlSource.yunzhuo,
  ),
).called(1);
```

断使能后：

```dart
enabledCtrl.add(false);
async.flushMicrotasks();
expect(handover.isSuspended, isTrue);

when(() => joint.position).thenReturn(freshPosition);
when(() => arbiter.state).thenReturn(
  Walking(Stream<History>.empty().listen((_) {})),
);
enabledCtrl.add(true);
async.flushMicrotasks();
expect(handover.preview(policyAction).action.values, freshPosition.discardFoot().values);
```

- [ ] **Step 2: 运行测试，确认 RED**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog/test/real_control_dog_test.dart --reporter expanded
```

Expected: compile/behavior FAIL，`RealControlDog` 尚未接受 handover 或冻结命令。

- [ ] **Step 3: 修改 RealControlDog**

构造器增加：

```dart
BodyHeightHandover? bodyHeightHandover,
```

Body-height profile 必须同时具有 `BodyHeightAxisInput` 和非空 handover。
Standing 中任一摇杆请求时，先让内部 `sendCommand` 返回仲裁器的 `bool`
结果，再按以下顺序执行：

1. 通过仲裁器发送 `A.setBodyHeight(_defaultBodyHeight)`；
2. 把 `_bodyHeightTarget` 重置为默认值；
3. 把 `_bodyHeightAxis` 清零；
4. 调用 `handover.requestFrom(joint.position)`，此处立即固定 `q_start`；
5. 只发送 `A.walk(Vector3.zero())`；
6. height 或 walk 任一命令被拒绝时调用 `handover.cancel()`；height 被拒绝时
   不再发送 walk。

stateStream 收到 Walking 且 handover 为 requested 时：

```dart
handover.begin();
```

handover 阻塞期间，direction handler 直接返回；body-height axis handler
必须把 `_bodyHeightAxis` 保持为 0，tick 也直接返回，禁止缓存旧轴值。
L1/L2/R1 先 `cancel()`，再走现有命令。H=false 和红键都先清零轴、调用
`suspend()`，并调用 `onMotorEnableChanged(false)`；H=true 且状态仍为
Walking 时调用 `restartFrom(joint.position)`，若仍为 Standing/Grounded
则取消并等待新的摇杆请求。Grounded、Zero、意外 Transitioning、故障或其他
离开 Walking 的状态按上表处理，尤其必须取消 requested/running/suspended，
但 requested 收到 Standing 时保持等待。Walking 的自动增益切换在 handover
阻塞时跳过，由每个输出帧设置同权重增益。

- [ ] **Step 4: 先写真实输出顺序的失败测试**

创建 `motor_action_dispatcher_test.dart`，用 closure 记录 gate、send 和 gain
写入顺序。至少包含：

```dart
test('disabled and Grounded outputs never advance the handover', () {
  final handover = buildHandover()
    ..requestFrom(startAction)
    ..begin();
  final sent = <JointsMatrix>[];
  final dispatcher = MotorActionDispatcher(
    handover: handover,
    gateAction: (desired, measured) => desired,
    sendAction: sent.add,
    setGains: (_, _) {},
  );

  dispatcher.dispatch(
    outputEnabled: false,
    grounded: false,
    policyAction: policyAction,
    measuredPosition: startAction,
  );
  expect(handover.preview(policyAction).frameIndex, 0);
  expect(sent, isEmpty);

  dispatcher.dispatch(
    outputEnabled: true,
    grounded: true,
    policyAction: policyAction,
    measuredPosition: startAction,
  );
  expect(handover.preview(policyAction).frameIndex, 0);
  expect(sent.single.values, startAction.discardFoot().values);
});

test('frame 100 is sent before command blocking is released', () {
  final handover = buildHandover()
    ..requestFrom(startAction)
    ..begin();
  final sent = <JointsMatrix>[];
  final dispatcher = buildDispatcher(handover, sent);

  for (var sample = 0; sample <= 100; sample++) {
    expect(handover.blocksControllerCommands, isTrue);
    dispatcher.dispatch(
      outputEnabled: true,
      grounded: false,
      policyAction: policyAction,
      measuredPosition: startAction,
    );
  }

  expect(sent, hasLength(101));
  expect(sent.first.values, startAction.discardFoot().values);
  expect(sent.last.values, policyAction.values);
  expect(handover.blocksControllerCommands, isFalse);
});

for (final failingStage in ['gain', 'gate', 'send']) {
  test('$failingStage failure does not advance frame 0', () {
    final handover = buildHandover()
      ..requestFrom(startAction)
      ..begin();
    final events = <String>[];
    final dispatcher = MotorActionDispatcher(
      handover: handover,
      gateAction: (desired, measured) {
        events.add('gate');
        if (failingStage == 'gate') throw StateError('gate failed');
        return desired;
      },
      sendAction: (desired) {
        events.add('send');
        if (failingStage == 'send') throw StateError('send failed');
      },
      setGains: (_, _) {
        events.add('gain');
        if (failingStage == 'gain') throw StateError('gain failed');
      },
    );

    expect(
      () => dispatcher.dispatch(
        outputEnabled: true,
        grounded: false,
        policyAction: policyAction,
        measuredPosition: startAction,
      ),
      throwsStateError,
    );
    expect(handover.preview(policyAction).frameIndex, 0);
    if (failingStage == 'gain') {
      expect(events, ['gain']);
    }
  });
}
```

- [ ] **Step 5: 运行 dispatcher 测试，确认 RED**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog/test/motor_action_dispatcher_test.dart --reporter expanded
```

Expected: compile FAIL，`MotorActionDispatcher` 尚不存在。

- [ ] **Step 6: 实现并接入可测试输出门**

创建：

```dart
typedef MotorActionGate =
    JointsMatrix Function(JointsMatrix desired, JointsMatrix measured);
typedef MotorActionSender = void Function(JointsMatrix desired);
typedef MotorGainWriter =
    void Function(JointsMatrix kp, JointsMatrix kd);

final class MotorActionDispatcher {
  final BodyHeightHandover? handover;
  final MotorActionGate gateAction;
  final MotorActionSender sendAction;
  final MotorGainWriter setGains;

  const MotorActionDispatcher({
    required this.handover,
    required this.gateAction,
    required this.sendAction,
    required this.setGains,
  });

  bool dispatch({
    required bool outputEnabled,
    required bool grounded,
    required JointsMatrix policyAction,
    required JointsMatrix measuredPosition,
  }) {
    if (!outputEnabled) return false;
    if (grounded) {
      sendAction(measuredPosition.discardFoot());
      return true;
    }

    var desired = policyAction;
    final activeHandover = handover;
    final appliesHandover =
        activeHandover != null && activeHandover.isRunning;
    if (appliesHandover) {
      final frame = activeHandover.preview(policyAction);
      desired = frame.action;
      setGains(frame.kp, frame.kd);
    }

    final gated = gateAction(desired, measuredPosition);
    sendAction(gated);
    if (appliesHandover) {
      activeHandover.markApplied();
    }
    return true;
  }
}
```

导出该文件。`han_dog.dart` 根据默认 profile 创建共享
`BodyHeightHandover`，并创建：

```dart
final actionDispatcher = MotorActionDispatcher(
  handover: bodyHeightHandover,
  gateAction: motorHealth.gateAction,
  sendAction: joint.sendAction,
  setGains: (kp, kd) {
    joint.kpExt = kp;
    joint.kdExt = kd;
  },
);
```

`nextActionStream` 回调只调用：

```dart
actionDispatcher.dispatch(
  outputEnabled: motorOutputEnabled,
  grounded: arbiter.state is Grounded,
  policyAction: action,
  measuredPosition: joint.position,
);
```

同一个 handover 传给两个 `RealControlDog` 创建点。这样 disabled、Grounded、
gain/gate/send 任一异常均由单元测试证明不推进；gain 失败时还必须证明没有
继续 gate/send，frame 100 成功发送后才解除命令冻结。

- [ ] **Step 7: 运行全部接管测试，确认 GREEN**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' test han_dog/test/real_control_dog_test.dart han_dog/test/body_height_handover_test.dart han_dog/test/motor_action_dispatcher_test.dart --reporter expanded
```

Expected: 遥控生命周期、101 个成功发送样本/100 个间隔、异常不推进和纯
handover 测试全部 PASS。

- [ ] **Step 8: 提交运行时接管**

```powershell
git add -- han_dog/lib/src/real_control_dog.dart han_dog/lib/src/motor_action_dispatcher.dart han_dog/lib/han_dog.dart han_dog/bin/han_dog.dart han_dog/test/real_control_dog_test.dart han_dog/test/motor_action_dispatcher_test.dart
$expected = @(
  'han_dog/bin/han_dog.dart'
  'han_dog/lib/han_dog.dart'
  'han_dog/lib/src/motor_action_dispatcher.dart'
  'han_dog/lib/src/real_control_dog.dart'
  'han_dog/test/motor_action_dispatcher_test.dart'
  'han_dog/test/real_control_dog_test.dart'
) | Sort-Object
$actual = @(git diff --cached --name-only) | Sort-Object
if (@(Compare-Object $expected $actual).Count -ne 0) {
  throw "staged files differ from Task 6 allowlist`n$($actual -join "`n")"
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Task 6 staged diff check failed' }
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(bodyheight): blend standing into policy output"
if ($LASTEXITCODE -ne 0) { throw 'Task 6 commit failed' }
```

## Task 7: 文档、安全离线验证、推送与机器人非运动同步

**Files:**

- Modify: `README.md`
- Modify: `docs/BODYHEIGHTCTRL.md`
- Verify all files from Tasks 1–6

- [ ] **Step 1: 更新用户文档**

文档必须明确：

- `standingPose` 是兼容字段；
- `standUpPose` 是 L1/R1/gesture 的物理目标；
- `policyDefaultPose` 是 observation 和 ONNX action 的训练零点；
- H15/H18 默认体高 `0.40 m`，范围 `0.20–0.54 m`；
- 右摇杆速率 `0.02 m/s`、死区 `0.10`；
- Body-height Standing → Walking 接管为 100 个实际下发间隔；
- 接管期间速度固定 0、体高固定 0.40 m；
- R2 在 Body-height 模式被拒绝，H15/H18 通过停止后重新
  `start h15`/`start h18` 切换；
- 服务启动本身不会使能电机或发送站立/行走命令。

- [ ] **Step 2: 格式化并检查 diff**

```powershell
& 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe' format han_dog/lib/src/body_height_handover.dart han_dog/lib/src/motor_action_dispatcher.dart han_dog/lib/src/app/robot_profile.dart han_dog/lib/src/app/profile_manager.dart han_dog/lib/src/real_control_dog.dart han_dog/lib/han_dog.dart han_dog/bin/han_dog.dart han_dog/bin/server.dart han_dog_brain/lib/src/brain.dart han_dog/test/body_height_handover_test.dart han_dog/test/motor_action_dispatcher_test.dart han_dog/test/body_height_profile_contract_test.dart han_dog/test/han_dog_test.dart han_dog/test/profile_manager_test.dart han_dog/test/real_control_dog_test.dart han_dog_brain/test/behaviour_test.dart
git diff --check
git status --short
```

Expected: formatter 完成；`git diff --check` 无输出。确认独立的
`real_controller.dart`、`controller_test.dart`、diagnostics 改动未暂存。

- [ ] **Step 3: 运行 Dart 静态检查和已审计的无硬件测试集**

```powershell
$dart = 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\tooling\dart-3.12.2\dart-sdk\bin\dart.exe'
$safeTests = @(
  'han_dog/test/body_height_handover_test.dart'
  'han_dog/test/body_height_profile_contract_test.dart'
  'han_dog/test/control_arbiter_test.dart'
  'han_dog/test/controller_test.dart'
  'han_dog/test/gain_manager_test.dart'
  'han_dog/test/han_dog_test.dart'
  'han_dog/test/motor_action_dispatcher_test.dart'
  'han_dog/test/pcan_leg_mapping_test.dart'
  'han_dog/test/profile_manager_test.dart'
  'han_dog/test/proto_convert_test.dart'
  'han_dog/test/real_control_dog_test.dart'
  'han_dog/test/sim_sensor_test.dart'
  'han_dog/test/unified_cms_server_test.dart'
  'han_dog_brain/test/behaviour_test.dart'
  'han_dog_brain/test/cms_test.dart'
  'han_dog_brain/test/gesture_test.dart'
  'han_dog_brain/test/memory_test.dart'
  'han_dog_brain/test/model_contract_test.dart'
  'han_dog_brain/test/model_info_test.dart'
  'han_dog_brain/test/observation_builder_test.dart'
)
& $dart analyze
if ($LASTEXITCODE -ne 0) { throw 'dart analyze failed' }
& $dart test @safeTests --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'safe Dart test set failed' }
```

Expected: analyze 0 issue；上述无硬件测试全部 PASS。不得用裸
`dart test` 代替：仓库根目录没有单一 `test/`，且
`serial_port/test`、`pcan/test` 会访问真实串口/PCAN，明确排除。

- [ ] **Step 4: 提交文档并推送已通过本地测试的分支**

```powershell
git add -- README.md docs/BODYHEIGHTCTRL.md
$expected = @('README.md', 'docs/BODYHEIGHTCTRL.md') | Sort-Object
$actual = @(git diff --cached --name-only) | Sort-Object
if (@(Compare-Object $expected $actual).Count -ne 0) {
  throw "staged files differ from Task 7 allowlist`n$($actual -join "`n")"
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Task 7 staged diff check failed' }
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "docs(bodyheight): document bumpless takeover"
if ($LASTEXITCODE -ne 0) { throw 'Task 7 commit failed' }
git push origin bodyheightctrl
if ($LASTEXITCODE -ne 0) { throw 'bodyheightctrl push failed' }
```

Expected: GitHub `bodyheightctrl` 包含 Tasks 1–7 的全部提交；提交 author 为
`hahadahe <911987281@qq.com>`。后续 ARM64/staging 若失败，只能追加修复提交
并重新推送，不能改写已推送历史。

- [ ] **Step 5: 在机器人创建隔离的无硬件 staging clone**

本机 PowerShell 使用本计划专属的固定目录，并在目录已存在时拒绝继续，避免把
后续命令中的临时变量误用为空字符串：

```powershell
$stage = '/home/bsrl1/brainstem-bodyheight-staging-20260726'
ssh -b 192.168.66.163 -o BatchMode=yes bsrl1@192.168.66.190 "test ! -e '$stage' && git clone --recurse-submodules --branch bodyheightctrl https://github.com/Kitjesen/brainstem.git '$stage' && mkdir -p '$stage/model' && cp -p /home/bsrl1/brainstem-bodyheightctrl/model/thunder_h15_model10400.onnx /home/bsrl1/brainstem-bodyheightctrl/model/thunder_h18_model5000.onnx '$stage/model/'"
if ($LASTEXITCODE -ne 0) { throw 'staging clone/model copy failed' }
$stage
```

Expected: `$stage` 精确为
`/home/bsrl1/brainstem-bodyheight-staging-20260726`；若该路径已存在则命令失败；
候选目录尚未被覆盖。

- [ ] **Step 6: 在 staging 校验模型并运行 ARM64 无硬件测试**

先从本机进入一个普通机器人 SSH shell：

```powershell
ssh -b 192.168.66.163 -o BatchMode=yes bsrl1@192.168.66.190
```

只在该 SSH shell 中运行：

```bash
set -euo pipefail
STAGE=/home/bsrl1/brainstem-bodyheight-staging-20260726
test "$(realpath -e "$STAGE")" = "$STAGE"
cd "$STAGE"
printf '%s\n' \
  'ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4  model/thunder_h15_model10400.onnx' \
  'd632413aa9ddf16b6c795377bdbbef69c454ba1cc77f8acb7d560f381cd84296  model/thunder_h18_model5000.onnx' \
  | sha256sum -c -

export LD_LIBRARY_PATH=/opt/onnxruntime/lib:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu
export THUNDER_H15_ONNX="$STAGE/model/thunder_h15_model10400.onnx"
export THUNDER_H18_ONNX="$STAGE/model/thunder_h18_model5000.onnx"
DART=/home/bsrl1/flutter/bin/dart
SAFE_TESTS=(
  han_dog/test/body_height_handover_test.dart
  han_dog/test/body_height_profile_contract_test.dart
  han_dog/test/control_arbiter_test.dart
  han_dog/test/controller_test.dart
  han_dog/test/gain_manager_test.dart
  han_dog/test/han_dog_test.dart
  han_dog/test/motor_action_dispatcher_test.dart
  han_dog/test/pcan_leg_mapping_test.dart
  han_dog/test/profile_manager_test.dart
  han_dog/test/proto_convert_test.dart
  han_dog/test/real_control_dog_test.dart
  han_dog/test/sim_sensor_test.dart
  han_dog/test/unified_cms_server_test.dart
  han_dog_brain/test/behaviour_test.dart
  han_dog_brain/test/cms_test.dart
  han_dog_brain/test/gesture_test.dart
  han_dog_brain/test/memory_test.dart
  han_dog_brain/test/model_contract_test.dart
  han_dog_brain/test/model_info_test.dart
  han_dog_brain/test/observation_builder_test.dart
)
"$DART" pub get
"$DART" analyze
"$DART" test "${SAFE_TESTS[@]}" --reporter expanded
"$DART" test han_dog_brain/test/body_height_onnx_smoke_test.dart --reporter expanded
```

Expected: 两个模型 hash 均 `OK`；analyze 0 issue；allowlist tests PASS；
H15 `[batch,58]` 和 H18
`[batch,580]` 两项 PASS。该命令不运行真实硬件入口。

- [ ] **Step 7: 从 staging 运行 MuJoCo 0.40 m 零速度验证**

`walk_grpc.py` 会发送仿真的 StandUp/SetBodyHeight/Walk RPC，因此客户端
不得直接连接机器人 IP。Windows PowerShell 5.1 会破坏原生命令参数中的
嵌套 Bash 引号，因此所有远端脚本先编码为 UTF-8/Base64，SSH 只接收无嵌套
引号的固定解码包装器。隐藏 SSH 子进程通过 .NET `Process` 启动，不使用会因
`NO_PROXY/no_proxy` 重复环境变量报错的 `Start-Process`。该子进程同时承载
`127.0.0.1:13148` tunnel 和 staging `server.dart`；所有 readiness、RPC 和
关闭动作放在同一个 `try/finally`。无论验证 PASS/FAIL，finally 都只终止经
PID/cwd/cmdline/port 验证的仿真进程，并等待超过其 15 s 优雅退出上限：

```powershell
Set-Location 'E:\007\1-研究生资料\1-科研\4-项目\Thunder\.safety-work\brainstem-bodyheightctrl'

function ConvertTo-RemoteBashCommand {
  param([Parameter(Mandatory)][string] $Script)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Script)
  $payload = [Convert]::ToBase64String($bytes)
  return "printf %s $payload | base64 -d | bash"
}

function Invoke-VerifiedMujocoProfile {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('thunder_h15', 'thunder_h18')]
    [string] $Profile,

    [Parameter(Mandatory)]
    [ValidateSet(
      'han_dog/profiles/thunder_h15.json',
      'han_dog/profiles/thunder_h18.json'
    )]
    [string] $ProfileJson
  )

  $sshExe = (Get-Command ssh -ErrorAction Stop).Source
  $remoteSimScript = 'set -euo pipefail; STAGE=/home/bsrl1/brainstem-bodyheight-staging-20260726; test "$(realpath -e "$STAGE")" = "$STAGE"; if ss -H -ltn "sport = :13147" | grep -q .; then echo "remote simulation port 13147 already in use" >&2; exit 1; fi; cd "$STAGE"; exec env LD_LIBRARY_PATH=/opt/onnxruntime/lib:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu MEDULLA_PORT=13147 MEDULLA_PROFILE_DIR="$STAGE/han_dog/profiles" MEDULLA_DEFAULT_PROFILE=' + $Profile + ' /home/bsrl1/flutter/bin/dart run han_dog/bin/server.dart'
  $remoteSim = ConvertTo-RemoteBashCommand $remoteSimScript
  $commonSshArgs = @(
    '-b', '192.168.66.163',
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=3',
    '-o', 'ConnectionAttempts=1'
  )
  $probeArgs = $commonSshArgs + @('bsrl1@192.168.66.190')
  $sshArgs = $commonSshArgs + @(
    '-o', 'ExitOnForwardFailure=yes',
    '-o', 'ServerAliveInterval=15',
    '-o', 'ServerAliveCountMax=3',
    '-L', '127.0.0.1:13148:127.0.0.1:13147',
    'bsrl1@192.168.66.190',
    $remoteSim
  )
  $pidProbeScript = 'set -euo pipefail; PIDS=$(ss -H -ltnp "sport = :13147" | sed -n "s/.*pid=\([0-9][0-9]*\).*/\1/p" | sort -u); test "$(printf "%s\n" "$PIDS" | sed "/^$/d" | wc -l)" -eq 1; PID=$PIDS; kill -0 "$PID"; test "$(readlink -f "/proc/$PID/cwd")" = /home/bsrl1/brainstem-bodyheight-staging-20260726; CMD=$(tr "\0" " " < "/proc/$PID/cmdline"); case "$CMD" in *han_dog/bin/server.dart*) ;; *) exit 1 ;; esac; ss -H -ltnp "sport = :13147" | grep -q "pid=$PID,"; START=$(sed "s/^[^)]*) //" "/proc/$PID/stat" | cut -d" " -f20); case "$START" in ""|*[!0-9]*) exit 1 ;; esac; printf "%s:%s" "$PID" "$START"'
  $pidProbe = ConvertTo-RemoteBashCommand $pidProbeScript

  $tunnel = $null
  $simPid = ''
  $simStart = ''
  $cleanupError = $null
  try {
    if (Get-NetTCPConnection -LocalPort 13148 -State Listen -ErrorAction SilentlyContinue) {
      throw 'local simulation tunnel port 13148 is already in use'
    }
    # 不访问 ProcessStartInfo.EnvironmentVariables，直接继承原始环境块，
    # 因而不会把 NO_PROXY/no_proxy 装入大小写不敏感字典。
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $sshExe
    $startInfo.Arguments = $sshArgs -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $tunnel = New-Object System.Diagnostics.Process
    $tunnel.StartInfo = $startInfo
    if (-not $tunnel.Start()) { throw 'failed to start simulation SSH tunnel' }

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $readyDeadline) {
      if ($tunnel.HasExited) {
        throw "simulation SSH/server exited before readiness: $($tunnel.ExitCode)"
      }
      $probeOutput = & $sshExe @probeArgs $pidProbe
      $probeLine = "$probeOutput".Trim()
      if ($LASTEXITCODE -eq 0 -and $probeLine -match '^([0-9]+):([0-9]+)$') {
        $simPid = $Matches[1]
        $simStart = $Matches[2]
        break
      }
      Start-Sleep -Milliseconds 200
    }
    if ($simPid -notmatch '^[0-9]+$' -or $simStart -notmatch '^[0-9]+$') {
      throw 'no uniquely verified staging simulation PID within 15s'
    }

    $profileProbe = "import sys,grpc; sys.path.insert(0,'brainstem_api/python'); from brainstem_api import RobotControlStub,Empty; c=grpc.insecure_channel('127.0.0.1:13148'); grpc.channel_ready_future(c).result(timeout=5); r=RobotControlStub(c).GetProfile(Empty(),timeout=5); assert r.current=='$Profile',r; print('verified simulation profile:',r.current)"
    & python -c $profileProbe
    if ($LASTEXITCODE -ne 0) {
      throw "$Profile simulation identity/readiness check failed"
    }

    & python sim/scripts/walk_grpc.py `
      --host 127.0.0.1 `
      --port 13148 `
      --profile $ProfileJson `
      --height 0.40 `
      --vx 0 `
      --vy 0 `
      --vyaw 0 `
      --duration 5
    if ($LASTEXITCODE -ne 0) { throw "$Profile MuJoCo validation failed" }
  } finally {
    if (
      ($simPid -notmatch '^[0-9]+$' -or $simStart -notmatch '^[0-9]+$') -and
      $tunnel -ne $null -and
      -not $tunnel.HasExited
    ) {
      $probeOutput = & $sshExe @probeArgs $pidProbe
      $probeLine = "$probeOutput".Trim()
      if ($LASTEXITCODE -eq 0 -and $probeLine -match '^([0-9]+):([0-9]+)$') {
        $simPid = $Matches[1]
        $simStart = $Matches[2]
      }
    }

    $hasIdentity =
      $simPid -match '^[0-9]+$' -and $simStart -match '^[0-9]+$'
    if ($hasIdentity) {
      $stopProbeScript = 'set -euo pipefail; PID=' + $simPid + '; START=' + $simStart + '; if test -d "/proc/$PID"; then CURRENT=$(sed "s/^[^)]*) //" "/proc/$PID/stat" | cut -d" " -f20); test "$CURRENT" = "$START"; test "$(readlink -f "/proc/$PID/cwd")" = /home/bsrl1/brainstem-bodyheight-staging-20260726; CMD=$(tr "\0" " " < "/proc/$PID/cmdline"); case "$CMD" in *han_dog/bin/server.dart*) ;; *) exit 1 ;; esac; ss -H -ltnp "sport = :13147" | grep -q "pid=$PID,"; kill -- "$PID"; fi'
      $stopProbe = ConvertTo-RemoteBashCommand $stopProbeScript
      & $sshExe @probeArgs $stopProbe
      if ($LASTEXITCODE -ne 0) {
        $cleanupError =
          'refused TERM: PID/start-time/cwd/cmdline/port identity changed'
      }
    } elseif ($tunnel -ne $null -and -not $tunnel.HasExited) {
      # 尚未发送任何仿真运动 RPC；关闭本次已知 SSH 子进程以触发远端 HUP。
      $cleanupError = 'simulation process started but no stable PID identity was captured'
      try { $tunnel.Kill() } catch {}
    }

    $closedProbeScript = if ($hasIdentity) {
      'set -euo pipefail; PID=' + $simPid + '; test ! -d "/proc/$PID"; if ss -H -ltn "sport = :13147" | grep -q .; then exit 1; fi'
    } else {
      'set -euo pipefail; if ss -H -ltn "sport = :13147" | grep -q .; then exit 1; fi'
    }
    $closedProbe = ConvertTo-RemoteBashCommand $closedProbeScript
    $closed = $false
    $graceDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $graceDeadline) {
      & $sshExe @probeArgs $closedProbe
      $remoteClosed = $LASTEXITCODE -eq 0
      $localClosed = -not (
        Get-NetTCPConnection -LocalPort 13148 -State Listen -ErrorAction SilentlyContinue
      )
      if ($remoteClosed -and $localClosed) {
        $closed = $true
        break
      }
      Start-Sleep -Milliseconds 200
    }

    if (-not $closed -and $hasIdentity) {
      # TERM 的 30 s 宽限期已超过。强杀前不依赖监听端口，而是重新核对
      # PID start-time、cwd 和 cmdline，防止 PID 复用误杀其他进程。
      $forceProbeScript = 'set -euo pipefail; PID=' + $simPid + '; START=' + $simStart + '; if test -d "/proc/$PID"; then CURRENT=$(sed "s/^[^)]*) //" "/proc/$PID/stat" | cut -d" " -f20); test "$CURRENT" = "$START"; test "$(readlink -f "/proc/$PID/cwd")" = /home/bsrl1/brainstem-bodyheight-staging-20260726; CMD=$(tr "\0" " " < "/proc/$PID/cmdline"); case "$CMD" in *han_dog/bin/server.dart*) ;; *) exit 1 ;; esac; kill -KILL -- "$PID"; fi'
      $forceProbe = ConvertTo-RemoteBashCommand $forceProbeScript
      & $sshExe @probeArgs $forceProbe
      if ($LASTEXITCODE -ne 0) {
        $cleanupError =
          'refused KILL: PID/start-time/cwd/cmdline identity changed'
      }
    }

    if ($tunnel -ne $null -and -not $tunnel.HasExited) {
      try { $tunnel.Kill() } catch {}
    }

    if (-not $closed) {
      $finalDeadline = [DateTime]::UtcNow.AddSeconds(10)
      while ([DateTime]::UtcNow -lt $finalDeadline) {
        & $sshExe @probeArgs $closedProbe
        $remoteClosed = $LASTEXITCODE -eq 0
        $localClosed = -not (
          Get-NetTCPConnection -LocalPort 13148 -State Listen -ErrorAction SilentlyContinue
        )
        if ($remoteClosed -and $localClosed) {
          $closed = $true
          break
        }
        Start-Sleep -Milliseconds 200
      }
    }
    if (-not $closed) {
      $cleanupError =
        'cleanup unverified: PID, remote 13147, or local 13148 remained/unreachable'
    }
    if ($cleanupError -ne $null) { throw $cleanupError }
  }
}

Invoke-VerifiedMujocoProfile `
  -Profile thunder_h15 `
  -ProfileJson han_dog/profiles/thunder_h15.json
Invoke-VerifiedMujocoProfile `
  -Profile thunder_h18 `
  -ProfileJson han_dog/profiles/thunder_h18.json
```

Expected: 两次退出码均为 0，`walkingTicks > 0`，observationDim 分别为
58/580，`bodyHeightCommand == 0.40`，无 non-finite/跌倒，且现有 METRICS
中的 `abs(y) <= 0.10 m`、`displacement <= 0.20 m`。记录 x、y、
final/minActive trunk height、maxAbsTorque 和 walkingTicks；MuJoCo 结果不
代表实机已验证。任一 PID/cwd/cmdline/profile/端口校验失败时，不得运行
`walk_grpc.py`。

- [ ] **Step 8: 同步前确认候选服务停止且工作区没有新漂移**

该步骤只读；从 `/home/bsrl1` 运行。服务状态只接受明确的
`inactive`/`failed`；`active`、`activating`、`reloading`、`deactivating`
或未知状态一律退出。`13145` 正在监听或候选目录中仍有 Dart 硬件进程时也
立即退出，不得自动 stop/restart：

```bash
set -euo pipefail
CANDIDATE=/home/bsrl1/brainstem-bodyheightctrl
test "$(realpath -e "$CANDIDATE")" = "$CANDIDATE"

for unit in han_dog.service han-dog-bodyheight.service; do
  state=$(systemctl is-active "$unit" 2>/dev/null || true)
  printf '%s: %s\n' "$unit" "$state"
  case "$state" in
    inactive|failed) ;;
    *) printf 'refusing sync: %s is %s\n' "$unit" "$state" >&2; exit 1 ;;
  esac
done
if ss -H -ltn "sport = :13145" | grep -q .; then
  echo 'refusing sync: port 13145 is listening' >&2
  exit 1
fi
for proc in /proc/[0-9]*; do
  cwd=$(readlink -f "$proc/cwd" 2>/dev/null || true)
  test "$cwd" = "$CANDIDATE" || continue
  cmd=$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)
  case "$cmd" in
    *dart*han_dog*) printf 'refusing sync: %s cwd=%s\n' "$cmd" "$cwd" >&2; exit 1 ;;
  esac
done

cd "$CANDIDATE"
printf '%s\n' \
  '9057376fc230bb6dd82f52479ab07bc46af8c1736ca9fd658747376de38e692d  han_dog/bin/han_dog.dart' \
  '80974618d6f12daab82002eef1734c95f19fb58d6daed21ef8558ace83da3471  han_dog/lib/src/app/profile_manager.dart' \
  'af5bb8f9339c1ffc965571d3a8251097bbf8ed22b5ba032aa3b15f7c7d9d5e86  han_dog/lib/src/real_control_dog.dart' \
  'de98df9c0d4b58b149f83a26eb5a4a4e990376e7686b3824c2098515e7a73483  han_dog/profiles/thunder_h15.json' \
  '73d68df00852e9af1650d19164e1d679e5f2699e8e11a527f513a277029802cb  han_dog/profiles/thunder_h18.json' \
  'eea976604d58957ec4ee7f92fbbcba4b7f773d2cf7a72e91ad746432426d1e16  han_dog/test/profile_manager_test.dart' \
  'a4526f2bc43dfc4ab5bd7f0f77a632f23511b1747de32c4b863844a6de269f27  han_dog/test/real_control_dog_test.dart' \
  '63ee322fcd508d07f7141169ec9e038a1cad04a10b30106513dc91ab860b50b7  han_dog/test/body_height_profile_contract_test.dart' \
  | sha256sum -c -
```

Expected: 两个服务都明确为 inactive/failed；端口 free；没有候选硬件进程；
八个文件全部 `OK`。任一不匹配都停止同步并先审阅新 diff，禁止覆盖。

- [ ] **Step 9: 从已验证 staging 只同步 allowlist 到候选目录**

在机器人 SSH shell 中设置并验证固定绝对路径：

```bash
set -euo pipefail
STAGE_PATH=/home/bsrl1/brainstem-bodyheight-staging-20260726
CANDIDATE=/home/bsrl1/brainstem-bodyheightctrl
test "$(realpath -e "$STAGE_PATH")" = /home/bsrl1/brainstem-bodyheight-staging-20260726
test "$(realpath -e "$CANDIDATE")" = /home/bsrl1/brainstem-bodyheightctrl
test -d "$STAGE_PATH/.git" && test -d "$CANDIDATE/.git"

for unit in han_dog.service han-dog-bodyheight.service; do
  state=$(systemctl is-active "$unit" 2>/dev/null || true)
  case "$state" in
    inactive|failed) ;;
    *) printf 'refusing sync: %s is %s\n' "$unit" "$state" >&2; exit 1 ;;
  esac
done
if ss -H -ltn "sport = :13145" | grep -q .; then
  echo 'refusing sync: port 13145 became active' >&2
  exit 1
fi
for proc in /proc/[0-9]*; do
  cwd=$(readlink -f "$proc/cwd" 2>/dev/null || true)
  test "$cwd" = "$CANDIDATE" || continue
  cmd=$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)
  case "$cmd" in
    *dart*han_dog*) printf 'refusing sync: %s cwd=%s\n' "$cmd" "$cwd" >&2; exit 1 ;;
  esac
done

FILES=(
  README.md
  docs/BODYHEIGHTCTRL.md
  han_dog/lib/han_dog.dart
  han_dog/lib/src/body_height_handover.dart
  han_dog/lib/src/motor_action_dispatcher.dart
  han_dog/lib/src/app/robot_profile.dart
  han_dog/lib/src/app/profile_manager.dart
  han_dog/lib/src/real_control_dog.dart
  han_dog/bin/han_dog.dart
  han_dog/bin/server.dart
  han_dog/profiles/thunder_h15.json
  han_dog/profiles/thunder_h18.json
  han_dog/test/body_height_handover_test.dart
  han_dog/test/motor_action_dispatcher_test.dart
  han_dog/test/body_height_profile_contract_test.dart
  han_dog/test/han_dog_test.dart
  han_dog/test/profile_manager_test.dart
  han_dog/test/real_control_dog_test.dart
  han_dog_brain/lib/src/brain.dart
  han_dog_brain/test/behaviour_test.dart
)

# 第一遍必须完整预检；此循环不写候选目录。
for file in "${FILES[@]}"; do
  test -f "$STAGE_PATH/$file"
done

# 所有源文件存在后才开始复制。
for file in "${FILES[@]}"; do
  mkdir -p "$CANDIDATE/$(dirname "$file")"
  cp -p -- "$STAGE_PATH/$file" "$CANDIDATE/$file"
done

# 每个目标必须与已验证 staging 逐字节一致。
for file in "${FILES[@]}"; do
  cmp -s -- "$STAGE_PATH/$file" "$CANDIDATE/$file"
done
```

该 allowlist 不包含机器人端 dirty 的 `real_controller.dart`、`monitoring.dart`、
`robo_device*`、服务脚本或串口代码。任一预检/复制/比对失败都因
`set -euo pipefail` 立即停止；候选服务仍保持停止，不得继续下一步。

- [ ] **Step 10: 候选目录只做非硬件复验**

```bash
set -euo pipefail
cd /home/bsrl1/brainstem-bodyheightctrl
export LD_LIBRARY_PATH=/opt/onnxruntime/lib:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu
export THUNDER_H15_ONNX=/home/bsrl1/brainstem-bodyheightctrl/model/thunder_h15_model10400.onnx
export THUNDER_H18_ONNX=/home/bsrl1/brainstem-bodyheightctrl/model/thunder_h18_model5000.onnx
printf '%s\n' \
  'ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4  model/thunder_h15_model10400.onnx' \
  'd632413aa9ddf16b6c795377bdbbef69c454ba1cc77f8acb7d560f381cd84296  model/thunder_h18_model5000.onnx' \
  | sha256sum -c -
/home/bsrl1/flutter/bin/dart analyze
/home/bsrl1/flutter/bin/dart test han_dog/test/body_height_handover_test.dart han_dog/test/motor_action_dispatcher_test.dart han_dog/test/body_height_profile_contract_test.dart han_dog/test/real_control_dog_test.dart --reporter expanded
/home/bsrl1/flutter/bin/dart test han_dog_brain/test/body_height_onnx_smoke_test.dart --reporter expanded
for unit in han_dog.service han-dog-bodyheight.service; do
  state=$(systemctl is-active "$unit" 2>/dev/null || true)
  printf '%s: %s\n' "$unit" "$state"
  case "$state" in
    inactive|failed) ;;
    *) printf 'unexpected service state: %s=%s\n' "$unit" "$state" >&2; exit 1 ;;
  esac
done
if ss -H -ltn "sport = :13145" | grep -q .; then
  echo 'unexpected listener on 13145 after sync' >&2
  exit 1
fi
for proc in /proc/[0-9]*; do
  cwd=$(readlink -f "$proc/cwd" 2>/dev/null || true)
  test "$cwd" = /home/bsrl1/brainstem-bodyheightctrl || continue
  cmd=$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)
  case "$cmd" in
    *dart*han_dog*) printf 'unexpected candidate process: %s\n' "$cmd" >&2; exit 1 ;;
  esac
done
```

Expected: 两个模型 hash `OK`，analyze、四个集成测试和 H15/H18 ONNX
smoke PASS；最后的服务/端口/进程命令只读且仍全部停止。不得执行
`bodyheight_service.sh start`、`stop`、`restore-master`、`systemctl restart`
或任何 gRPC motion RPC。

- [ ] **Step 11: 安全清理 staging 并确认远端分支**

```bash
set -euo pipefail
STAGE_PATH=/home/bsrl1/brainstem-bodyheight-staging-20260726
test "$(realpath -e "$STAGE_PATH")" = /home/bsrl1/brainstem-bodyheight-staging-20260726
test -d "$STAGE_PATH/.git"
if ss -H -ltn "sport = :13147" | grep -q .; then
  echo 'refusing cleanup: simulation port 13147 is still listening' >&2
  exit 1
fi
for proc in /proc/[0-9]*; do
  cwd=$(readlink -f "$proc/cwd" 2>/dev/null || true)
  test "$cwd" = "$STAGE_PATH" || continue
  cmd=$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)
  case "$cmd" in
    *dart*server.dart*) printf 'refusing cleanup: %s\n' "$cmd" >&2; exit 1 ;;
  esac
done
cd /home/bsrl1
test "$(pwd -P)" = /home/bsrl1
case "$(pwd -P)/" in
  "$STAGE_PATH"/*) echo 'refusing cleanup from inside staging' >&2; exit 1 ;;
esac
rm -rf -- "$STAGE_PATH"
test ! -e /home/bsrl1/brainstem-bodyheight-staging-20260726
git ls-remote --heads https://github.com/Kitjesen/brainstem.git bodyheightctrl
```

Expected: 只删除本计划的固定 staging；候选目录和模型未删除；远端
`bodyheightctrl` 指向已通过 staging 验证的最新提交。

## 完成标准

- legacy profile 不改 JSON 即保持旧行为；
- H15/H18 的 L1/R1 使用安全 `±0.8/±1.8`，策略 observation/action 使用训练
  `±1.1/±2.6`；
- H15/H18 默认体高均为 0.40 m，58/580 维模型契约不变；
- frame 0/50/100 的 action、wheel、Kp、Kd 使用同一 smoothstep；
- 只有完成一次 `sendAction` 路径后才推进，断使能时不推进；
- 重使能从新实测关节位置的 frame 0 重启；
- 接管期间速度和体高输入不缓存、不补发；
- L1/L2/R1、离开 Walking、故障和急停仍可抢占；
- GitHub 分支、机器人候选目录和设计规格一致；
- 未由自动化启动候选服务、使能电机或发送实机运动命令。

## 已知但不在本次范围内

- `ProfileManager` 在 Brain 已成功切换、随后 gain 切换失败时，现有外层回滚
  只恢复 gains/GestureLibrary，未重新加载旧 Brain 模型。这是既存的标准
  profile 热切换原子性问题；Body-height profile 已禁止热切换，因此不阻塞本次
  H15/H18 接管实现，后续应单独用模型回滚设计和测试修复。
- 本地 `real_controller.dart` watchdog 的取消/重监听竞态属于另一组正在审查
  的改动，不与本计划合并。
