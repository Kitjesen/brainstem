# Body-Height Remote Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `observationType == "bodyHeight"` 的 H15/H18 增加独立遥控器模式：保留现有速度、偏航和安全按键，用右摇杆 Y 轴以 0.08 m/s 连续调节 0.20–0.54 m 体高；非体高策略的现有行为保持不变。

**Architecture:** `RealControlDog` 继续拥有电机使能、急停、校零、状态增益和 profile 切换等公共安全职责，并根据活动 `RobotProfile` 创建 `LegacyRemoteMode` 或 `BodyHeightRemoteMode`。两个模式复用同一套既有运动按键绑定；体高模式额外订阅 `RealController` 暴露的故障安全右摇杆 Y 轴，并通过现有 `ControlArbiter` 发送 `Walk(0,0,0)` 和 `SetBodyHeight`。体高积分被拆成纯函数/小状态对象，以便完全离线、确定性测试。

**Tech Stack:** Dart 3.12、`dart:async`、RxDart（现有依赖）、`fake_async`、`test`、`mocktail`、现有 `han_dog_brain` CMS 和 `ControlArbiter`。

---

## 实施约束

- 不新增依赖、gRPC RPC、systemd 服务或机器人启动动作。
- 所有自动化测试只使用 mock/fake stream；不得打开 IMU、串口、PCAN，不得使能电机。
- `LegacyRemoteMode` 必须保持当前 57 维策略的方向、L1/L2/R1、CH5、红键、校零和 R2 语义。
- 体高命令只能通过
  `arbiter.command(A.setBodyHeight(value), ControlSource.yunzhuo)` 发送。
- H15/H18 的历史长度不同；当活动 profile 为 `bodyHeight` 时，R2 只记录“需重启服务切换”的拒绝，不调用热切换回调。H15/H18 继续通过
  `./scripts/bodyheight_service.sh start h15|h18` 选择。
- 所有 Git 提交只对单次命令使用
  `-c user.name=hahadahe -c user.email=911987281@qq.com`，不得修改仓库或全局默认 Git 身份。

## Task 1: 暴露带 150 ms watchdog 的体高轴

**Files:**

- Modify: `han_dog/lib/src/gamepad.dart`
- Modify: `han_dog/lib/src/real_controller.dart`
- Modify: `han_dog/test/controller_test.dart`

- [ ] **Step 1: 先写会失败的轴方向与 watchdog 测试**

在 `han_dog/test/controller_test.dart` 中保留现有通用
`watchdogDecay` 覆盖，并增加确定性测试。测试构造
`YunZhuoState.fromChannels`，确认 CH2 物理上推得到正值；再验证最后一次输入后
150 ms 以内保持、超时后归零：

```dart
import 'package:fake_async/fake_async.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

test('YUNZHUO right-stick up is a positive body-height axis', () {
  final channels = List<int>.filled(16, SbusValues.center);
  channels[1] = SbusValues.low;
  channels[4] = SbusValues.center;

  final state = YunZhuoState.fromChannels(channels, 0);

  expect(state.rightStick.y, closeTo(1.0, 1e-12));
});

test('body-height axis fails safe to zero after 150 ms', () {
  fakeAsync((async) {
    final input = StreamController<double>.broadcast(sync: true);
    final output = <double>[];
    bodyHeightAxisWithWatchdog(input.stream).listen(output.add);

    input.add(0.6);
    async.flushMicrotasks();
    expect(output.last, 0.6);

    async.elapse(const Duration(milliseconds: 149));
    expect(output.last, 0.6);

    async.elapse(const Duration(milliseconds: 2));
    expect(output.last, 0.0);
  });
});
```

- [ ] **Step 2: 运行测试，确认因缺少轴 API 而失败**

Run:

```bash
dart test han_dog/test/controller_test.dart --reporter expanded
```

Expected: compile failure mentioning
`bodyHeightAxisWithWatchdog` is not defined；`fakeAsync`、
`YunZhuoState` 和 `SbusValues` 已由本步骤新增的 imports 正确解析，不应出现
其他未定义符号。

- [ ] **Step 3: 增加窄能力接口并实现 RealController 轴流**

在 `gamepad.dart` 增加独立能力接口，不改变 Xbox 或其他 `Gamepad`
实现：

```dart
abstract interface class BodyHeightAxisInput {
  Stream<double> get bodyHeightAxis;
}
```

让 `RealController` 显式实现该能力，并将 watchdog 参数集中到一个可测试函数：

```dart
Stream<double> bodyHeightAxisWithWatchdog(Stream<double> input) =>
    input.switchMap(
      (axis) => Rx.concat<double>([
        Stream<double>.value(axis),
        Stream<double>.value(
          0.0,
        ).delay(const Duration(milliseconds: 150)),
      ]),
    );

class RealController implements Gamepad, BodyHeightAxisInput {
  @override
  Stream<double> get bodyHeightAxis =>
      bodyHeightAxisWithWatchdog(stateStream.map((state) => state.rightStick.y));
}
```

更新 `real_controller.dart` 的 CH2 注释，明确“上推为正、仅提供标准化输入，
不负责死区、积分、profile 或 FSM”。

- [ ] **Step 4: 运行轴测试并格式化**

Run:

```bash
dart format han_dog/lib/src/gamepad.dart han_dog/lib/src/real_controller.dart han_dog/test/controller_test.dart
dart test han_dog/test/controller_test.dart --reporter expanded
```

Expected: all tests pass；测试进程不访问任何设备节点。

- [ ] **Step 5: 提交轴契约**

```bash
git add han_dog/lib/src/gamepad.dart han_dog/lib/src/real_controller.dart han_dog/test/controller_test.dart
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(remote): expose fail-safe body-height axis"
```

## Task 2: 先锁住旧映射，再提取 LegacyRemoteMode

**Files:**

- Create: `han_dog/lib/src/remote_control/remote_control_mode.dart`
- Create: `han_dog/lib/src/remote_control/legacy_remote_mode.dart`
- Create: `han_dog/test/remote_control_mode_test.dart`
- Modify: `han_dog/lib/src/real_control_dog.dart`
- Modify: `han_dog/lib/han_dog.dart`
- Modify: `han_dog/test/real_control_dog_test.dart`

- [ ] **Step 1: 写 Legacy 模式回归测试**

在新测试文件中创建：

- 一个由 `StreamController` 驱动的 `_FakeGamepad`；
- `MockControlArbiter`；
- 标准 `RobotProfile`；
- 捕获 `A` 动作的测试辅助函数。

覆盖以下具名测试：

- `direction keeps deadzone, profile clamping and yunzhuo ownership`
- `zero direction sends Walk.zero only while Walking`
- `L1, L2 and R1 keep StandUp, SitDown and StandUp mappings`
- `non-finite direction is ignored`
- `does not subscribe to body-height axis`
- `updated velocity bounds affect the next command without recreating the mode`
- `dispose cancels every mode subscription`
- `RealControlDog.dispose stops active-mode direction and R1 events`

“不订阅体高轴”使用计数型 stream：

```dart
expect(fakeGamepad.bodyHeightListenCount, 0);
```

- [ ] **Step 2: 运行测试，确认新模式尚不存在**

Run:

```bash
dart test han_dog/test/remote_control_mode_test.dart --reporter expanded
```

Expected: compile/import failure because
`remote_control/remote_control_mode.dart` and `LegacyRemoteMode` do not exist.

- [ ] **Step 3: 定义最小模式边界**

在 `remote_control_mode.dart` 定义不接触硬件的上下文和生命周期：

```dart
typedef RemoteCommandSender = bool Function(A action, String label);
typedef RemoteStreamErrorHandler =
    void Function(Object error, StackTrace stackTrace, String streamName);

class RemoteControlModeContext {
  final Gamepad controller;
  final ControlArbiter arbiter;
  final RemoteCommandSender sendCommand;
  final RemoteStreamErrorHandler onStreamError;

  const RemoteControlModeContext({
    required this.controller,
    required this.arbiter,
    required this.sendCommand,
    required this.onStreamError,
  });
}

abstract interface class RemoteControlMode {
  void start();
  void updateVelocityBounds({
    required (double, double, double) minimum,
    required (double, double, double) maximum,
  });
  void dispose();
}

void validateRemoteVelocityBounds(
  (double, double, double) minimum,
  (double, double, double) maximum,
) {
  final mins = [minimum.$1, minimum.$2, minimum.$3];
  final maxs = [maximum.$1, maximum.$2, maximum.$3];
  for (var index = 0; index < mins.length; index++) {
    if (!mins[index].isFinite ||
        !maxs[index].isFinite ||
        mins[index] > maxs[index]) {
      throw ArgumentError(
        'Velocity command bounds must be finite and ordered at axis $index',
      );
    }
  }
}
```

`start()` 必须幂等；`dispose()` 必须幂等并取消本模式拥有的全部 subscription。
最终设计需要的 `updateProfile(RobotProfile)` 在 Task 5 引入；Task 2 尚未给
`RealControlDog` 增加 profile 参数，因此不提前声明一个无法正确调用的方法。

- [ ] **Step 4: 把现有方向和 L1/L2/R1 原样搬入 LegacyRemoteMode**

`LegacyRemoteMode`：

- 通过构造器接收当前速度上下界；
- 以现有 `0.02` 方向死区处理 vx/vy/yaw；
- 方向全零时，仅在 `Walking` 发送一次对应输入事件的 `Walk.zero`；
- 非零方向继续发送 `A.walk(Vector3(vx, vy, yaw))`；
- L1/L2/R1 分别发送 `StandUp/SitDown/StandUp`；
- 所有命令使用注入的 `sendCommand`；
- 所有流错误使用注入的 `onStreamError`。

为体高模式后续复用 R1，构造器接受可选成功回调：

```dart
LegacyRemoteMode({
  required this.context,
  required (double, double, double) velocityCommandMin,
  required (double, double, double) velocityCommandMax,
  this.onReturnStandingAccepted,
});

final void Function()? onReturnStandingAccepted;

void updateVelocityBounds({
  required (double, double, double) minimum,
  required (double, double, double) maximum,
}) {
  validateRemoteVelocityBounds(minimum, maximum);
  _velocityCommandMin = minimum;
  _velocityCommandMax = maximum;
}

void _returnStanding() {
  final accepted = context.sendCommand(
    const A.standUp(),
    'standUp(R1)',
  );
  if (accepted) onReturnStandingAccepted?.call();
}
```

- [ ] **Step 5: RealControlDog 只保留公共安全绑定**

将 `RealControlDog` 中下列订阅移交给当前 mode：

- `controller.direction`
- `controller.standup`
- `controller.sitdown`
- `controller.idle`

以下逻辑原地保留且只绑定一次：

- `arbiter.stateStream` 的 kp/kd 切换；
- `controller.enabled`；
- `controller.red`；
- `controller.calibrate`；
- `controller.switchProfile`；
- stream error → `arbiter.fault`；
- `dispose()`。

`RealControlDog.dispose()` 必须先调用 `_remoteMode?.dispose()` 并清空 mode
引用，再取消公共 subscriptions。扩展现有 dispose 测试：保存 dog 引用并调用
`dispose()` 后继续向 direction 和 R1 stream 发事件，断言
`arbiter.command` 调用次数不再增加。

把原构造器局部函数提升为私有方法，以供 mode context 调用：

```dart
bool _sendCommand(A action, String label) {
  final accepted = arbiter.command(action, ControlSource.yunzhuo);
  if (!accepted) {
    _log.warning('YUNZHUO $label rejected — arbiter owner: ${arbiter.owner}');
  }
  return accepted;
}
```

此任务先始终创建 `LegacyRemoteMode`，不引入体高分支。
创建时传入 `RealControlDog` 已有的 `velocityCommandMin/Max`。现有
`RealControlDog.switchVelocityBounds` 在更新自身字段后，必须调用当前
`RemoteControlMode.updateVelocityBounds`，使 `ProfileManager` 的现有
profile 切换路径和直接调用者都立即使用新范围；不得等到 Task 5 才恢复这一
行为。把 `RealControlDog` 现有私有 `_validateVelocityBounds` 的调用替换为
上述 `validateRemoteVelocityBounds`，删除重复实现，确保 host 和 mode 使用
同一校验规则。

- [ ] **Step 6: 导出模式类型并运行回归**

在 `han_dog/lib/han_dog.dart` 导出新增模式文件。运行：

```bash
dart format han_dog/lib/src/remote_control han_dog/lib/src/real_control_dog.dart han_dog/lib/han_dog.dart han_dog/test/remote_control_mode_test.dart han_dog/test/real_control_dog_test.dart
dart test han_dog/test/remote_control_mode_test.dart --reporter expanded
dart test han_dog/test/real_control_dog_test.dart --reporter expanded
```

Expected: 新 Legacy 测试和现有 `RealControlDog` 安全/按钮回归全部通过。

- [ ] **Step 7: 提交行为保持型提取**

```bash
git add han_dog/lib/src/remote_control han_dog/lib/src/real_control_dog.dart han_dog/lib/han_dog.dart han_dog/test/remote_control_mode_test.dart han_dog/test/real_control_dog_test.dart
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "refactor(remote): extract legacy controller mode"
```

## Task 3: 以纯函数实现体高死区、积分和边界

**Files:**

- Create: `han_dog/lib/src/remote_control/body_height_integrator.dart`
- Create: `han_dog/test/body_height_integrator_test.dart`
- Modify: `han_dog/lib/han_dog.dart`

- [ ] **Step 1: 先写完整数学契约测试**

增加以下具名测试：

- `0.10 deadzone maps to zero`
- `deadzone exterior is linearly remapped without a jump`
- `full positive axis changes height at 0.08 m/s`
- `full negative axis lowers height`
- `delta time is capped at 100 ms`
- `target clamps to profile minimum and maximum`
- `non-finite axis and negative duration preserve the last safe target`
- `invalid or non-finite bounds and initial target are rejected`
- `reset replaces the target only with a finite in-range value`

使用明确数值断言：

```dart
expect(remapBodyHeightAxis(0.10), 0.0);
expect(remapBodyHeightAxis(-0.10), 0.0);
expect(remapBodyHeightAxis(0.55), closeTo(0.5, 1e-12));

final integrator = BodyHeightIntegrator(
  initialTarget: 0.35,
  minimum: 0.20,
  maximum: 0.54,
);
expect(
  integrator.advance(axis: 1.0, elapsed: const Duration(milliseconds: 20)),
  closeTo(0.3516, 1e-12),
);
```

- [ ] **Step 2: 运行测试，确认实现缺失**

Run:

```bash
dart test han_dog/test/body_height_integrator_test.dart --reporter expanded
```

Expected: compile/import failure because `BodyHeightIntegrator` is undefined.

- [ ] **Step 3: 实现无 IO 的积分器**

核心常量：

```dart
const bodyHeightAxisDeadzone = 0.10;
const bodyHeightRateMetersPerSecond = 0.08;
const bodyHeightMaxElapsed = Duration(milliseconds: 100);

void validateBodyHeightRange({
  required double initialTarget,
  required double minimum,
  required double maximum,
}) {
  if (!initialTarget.isFinite ||
      !minimum.isFinite ||
      !maximum.isFinite ||
      minimum > maximum ||
      initialTarget < minimum ||
      initialTarget > maximum) {
    throw ArgumentError('Body-height target and bounds must be finite and ordered');
  }
}
```

死区外重映射：

```dart
double remapBodyHeightAxis(double raw) {
  if (!raw.isFinite) return 0.0;
  final value = raw.clamp(-1.0, 1.0).toDouble();
  if (value.abs() <= bodyHeightAxisDeadzone) return 0.0;
  final magnitude =
      (value.abs() - bodyHeightAxisDeadzone) /
      (1.0 - bodyHeightAxisDeadzone);
  return value.isNegative ? -magnitude : magnitude;
}
```

`BodyHeightIntegrator` 校验初始值与上下界均为有限值且有序；`advance`
将 elapsed 截断到 `[0, 100 ms]`，按 0.08 m/s 积分并 clamp；`reset`
用于 profile 切换和 R1 站立后复位：

```dart
class BodyHeightIntegrator {
  final double minimum;
  final double maximum;
  double _target;

  BodyHeightIntegrator({
    required double initialTarget,
    required this.minimum,
    required this.maximum,
  }) : _target = initialTarget {
    validateBodyHeightRange(
      initialTarget: initialTarget,
      minimum: minimum,
      maximum: maximum,
    );
  }

  double get target => _target;

  void reset(double value) {
    if (!value.isFinite || value < minimum || value > maximum) {
      throw ArgumentError.value(value, 'value', 'must be finite and in range');
    }
    _target = value;
  }

double advance({required double axis, required Duration elapsed}) {
  final mapped = remapBodyHeightAxis(axis);
  final boundedMicros = elapsed.inMicroseconds.clamp(
    0,
    bodyHeightMaxElapsed.inMicroseconds,
  );
  final seconds = boundedMicros / Duration.microsecondsPerSecond;
  _target = (_target + mapped * bodyHeightRateMetersPerSecond * seconds)
      .clamp(minimum, maximum)
      .toDouble();
  return _target;
}
}
```

- [ ] **Step 4: 运行纯单元测试**

```bash
dart format han_dog/lib/src/remote_control/body_height_integrator.dart han_dog/test/body_height_integrator_test.dart han_dog/lib/han_dog.dart
dart test han_dog/test/body_height_integrator_test.dart --reporter expanded
```

Expected: all tests pass，无真实时间等待。

- [ ] **Step 5: 提交积分核心**

```bash
git add han_dog/lib/src/remote_control/body_height_integrator.dart han_dog/test/body_height_integrator_test.dart han_dog/lib/han_dog.dart
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(remote): add bounded body-height integrator"
```

## Task 4: 实现 BodyHeightRemoteMode 状态机

**Files:**

- Create: `han_dog/lib/src/remote_control/body_height_remote_mode.dart`
- Modify: `han_dog/test/remote_control_mode_test.dart`
- Modify: `han_dog/lib/han_dog.dart`

- [ ] **Step 1: 写状态与并发命令测试**

在 `remote_control_mode_test.dart` 增加 `BodyHeightRemoteMode` 组。向 mode
注入手动 `tickController.stream` 和可控单调时间函数，避免真实 50 Hz 等待：

```dart
var elapsed = Duration.zero;
Duration now() => elapsed;
void advance(Duration delta) {
  elapsed += delta;
  tickController.add(null);
}
```

逐项覆盖：

1. `Zero/Grounded/Transitioning` 忽略轴；
2. `Standing` 第一次离开死区仅发送一次 `Walk.zero`；
3. 状态仍为 `Standing` 时后续 tick 不重复发送；
4. 变为 `Walking` 后下一 tick 才发送 `SetBodyHeight`；
5. 右摇杆体高与左摇杆非零速度可以同时发送，且体高不发送额外
   `Walk.zero` 覆盖速度；
6. 回中后停止发送新体高并保留最后目标；
7. 达到 profile 上下界不越界；
8. R1 被接受后，先发送 `StandUp`，只在状态流确认 `Standing` 后发送一次
   profile 默认 `SetBodyHeight(0.35)`；
9. R1 被仲裁器拒绝时不安排复位；
10. R1 复位后下一次体高积分从 0.35 m 开始，而不是从复位前目标开始；
11. `dispose()` 后 tick、轴和状态流不再产生命令；
12. axis stream error 进入现有 `onStreamError`/fault 路径。

- [ ] **Step 2: 运行测试，确认模式缺失**

```bash
dart test han_dog/test/remote_control_mode_test.dart --reporter expanded
```

Expected: compile/import failure because `BodyHeightRemoteMode` does not exist.

- [ ] **Step 3: 实现体高模式并复用 Legacy 运动绑定**

`BodyHeightRemoteMode` 组合一个 `LegacyRemoteMode`，而不是复制方向与
L1/L2/R1 代码：

```dart
class BodyHeightRemoteMode implements RemoteControlMode {
  final RemoteControlModeContext context;
  final Stream<void> _ticks;
  final Duration Function()? _monotonicNow;

  LegacyRemoteMode? _legacy;
  BodyHeightIntegrator? _integrator;
  RobotProfile? _profile;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Stopwatch _stopwatch = Stopwatch()..start();

  double _axis = 0.0;
  Duration? _previousTick;
  bool _walkingRequested = false;
  bool _resetAfterStanding = false;

  BodyHeightRemoteMode({
    required this.context,
    Stream<void>? ticks,
    Duration Function()? monotonicNow,
  }) : _ticks =
           ticks ??
           Stream<void>.periodic(const Duration(milliseconds: 20)),
       _monotonicNow = monotonicNow;

  Duration _now() => _monotonicNow?.call() ?? _stopwatch.elapsed;
}
```

生产默认使用构造器中的 20 ms periodic stream 和单个持续运行的
`Stopwatch`；不得在每个 tick 新建 `Stopwatch`。

`start()`：

- 验证 `context.controller is BodyHeightAxisInput`，否则抛出
  `StateError`，使配置失败而不是静默运行一个不可控体高模式；
- 要求 `updateProfile` 已先提供合法 body-height profile；
- 启动 `_legacy`，传入 `onReturnStandingAccepted` 来设置
  `_resetAfterStanding = true`；
- 把 `_previousTick` 初始化为 `_now()`；
- 订阅体高轴、状态流和 50 Hz ticks。

每次 tick 都先计算 bounded delta 并立即更新 `_previousTick`，包括
Grounded/Standing/Transitioning 和轴回中的 tick；这样在状态长期不允许体高
控制后进入 Walking 时，不会累计一段很大的旧时间。

tick 处理严格按状态分支：

```dart
switch (context.arbiter.state) {
  case Standing():
    if (remapBodyHeightAxis(_axis) == 0.0) {
      _walkingRequested = false;
    } else if (!_walkingRequested) {
      _walkingRequested = true;
      context.sendCommand(
        A.walk(Vector3.zero()),
        'bodyHeight enter walking',
      );
    }
  case Walking():
    _walkingRequested = false;
    final integrator = _integrator!;
    final previousTarget = integrator.target;
    final next = integrator.advance(axis: _axis, elapsed: delta);
    if (remapBodyHeightAxis(_axis) != 0.0 &&
        next != previousTarget) {
      context.sendCommand(A.setBodyHeight(next), 'setBodyHeight');
    }
  case Zero() || Grounded() || Transitioning():
    _walkingRequested = false;
}
```

状态订阅在 `_resetAfterStanding && state is Standing` 时发送且仅发送一次
`A.setBodyHeight(profile.bodyHeightCommand)`；发送被拒绝时保留 pending，
但不得忙循环，只能在下一次 `Standing` 状态事件时重试。`updateProfile`
代表目标 profile 已改变，因此按下述规则清除旧 pending，不重试旧 profile 的
默认值。

`updateProfile` 必须：

- 验证 `observationType == "bodyHeight"`；
- 首次调用时用 profile 速度范围创建 `_legacy`，后续调用必须执行
  `_legacy!.updateVelocityBounds`，并分别传入 `profile.velocityCommandMin`
  与 `profile.velocityCommandMax`；
- 重新建立积分器范围，并把 `_profile` 指向新 profile；
- 目标复位到该 profile 的 `bodyHeightCommand`；
- 清除 `_walkingRequested`、`_resetAfterStanding` 和旧 tick 时间。

`start` 必须先检查 `_profile`、`_legacy` 和 `_integrator` 均已由
`updateProfile` 配置；`dispose` 必须取消自身所有 subscriptions、调用
`_legacy?.dispose()` 并停止 `_stopwatch`。
`updateVelocityBounds` 必须委托给 `_legacy`，保证
`RealControlDog.switchVelocityBounds` 在 body-height 模式中也不失效。

状态订阅确认 `Standing` 后，只有默认体高命令被仲裁器接受时才执行：

```dart
_integrator!.reset(_profile!.bodyHeightCommand);
_resetAfterStanding = false;
```

由此保证下一次推杆从默认 0.35 m 继续积分。

- [ ] **Step 4: 运行模式测试和既有 CMS 测试**

```bash
dart format han_dog/lib/src/remote_control/body_height_remote_mode.dart han_dog/test/remote_control_mode_test.dart han_dog/lib/han_dog.dart
dart test han_dog/test/remote_control_mode_test.dart --reporter expanded
dart test han_dog_brain/test/cms_test.dart --reporter expanded
```

Expected: all tests pass；`cms_test.dart` 证明 `SetBodyHeight` 的现有安全状态
规则未改变。

- [ ] **Step 5: 提交体高模式**

```bash
git add han_dog/lib/src/remote_control/body_height_remote_mode.dart han_dog/test/remote_control_mode_test.dart han_dog/lib/han_dog.dart
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(remote): add body-height controller mode"
```

## Task 5: 按活动 profile 选模并处理安全切换

**Files:**

- Modify: `han_dog/lib/src/remote_control/remote_control_mode.dart`
- Modify: `han_dog/lib/src/remote_control/legacy_remote_mode.dart`
- Modify: `han_dog/lib/src/remote_control/body_height_remote_mode.dart`
- Modify: `han_dog/lib/src/real_control_dog.dart`
- Modify: `han_dog/lib/src/app/profile_manager.dart`
- Modify: `han_dog/bin/han_dog.dart`
- Modify: `han_dog/example/demo_full_controller.dart`
- Modify: `han_dog/test/real_control_dog_test.dart`
- Modify: `han_dog/test/profile_manager_test.dart`

- [ ] **Step 1: 写 profile 选模和旧模式释放测试**

扩展 `real_control_dog_test.dart`，增加以下具名测试：

- `standard profile starts LegacyRemoteMode`
- `H15 bodyHeight profile starts BodyHeightRemoteMode`
- `H18 bodyHeight profile starts BodyHeightRemoteMode`
- `switchRemoteProfile disposes the previous mode before starting the next`
- `bodyHeight R2 is rejected with restart-required semantics`
- `legacy R2 still calls the existing profile switch callback`
- `bodyHeight commands reach the arbiter as ControlSource.yunzhuo`
- `invalid bodyHeight bounds or initial target are rejected before mode start`

扩展 `profile_manager_test.dart`，增加以下具名测试：

- `successful switch updates RealControlDog remote profile`
- `failed switch rollback restores previous RealControlDog remote profile`
- `bodyHeight profile is rejected before Brain switch when axis is unavailable`
- `runtime switch involving bodyHeight profile requires a service restart`
- `legacy R2 toggle skips bodyHeight profiles and cycles standard profiles`

为 `MockRealControlDog` 增加：

```dart
setUpAll(() {
  registerFallbackValue(
    RobotProfile(
      name: 'fallback',
      modelPath: 'fallback.onnx',
      standingPose: JointsMatrix.zero(),
      sittingPose: JointsMatrix.zero(),
      inferKp: JointsMatrix.zero(),
      inferKd: JointsMatrix.zero(),
      standUpKp: JointsMatrix.zero(),
      standUpKd: JointsMatrix.zero(),
      sitDownKp: JointsMatrix.zero(),
      sitDownKd: JointsMatrix.zero(),
    ),
  );
});

when(() => controlDog.validateRemoteProfile(any())).thenReturn(null);
when(() => controlDog.switchRemoteProfile(any())).thenReturn(null);
```

选模测试不依赖私有类型 getter：standard profile 断言体高轴订阅计数为 0，
H15/H18 断言计数为 1；切换/释放测试在保存旧 stream 后继续发事件，断言不再
产生任何 `arbiter.command`，从外部证明旧模式已释放。

- [ ] **Step 2: 运行测试，确认新接线尚未实现**

```bash
dart test han_dog/test/real_control_dog_test.dart han_dog/test/profile_manager_test.dart --reporter expanded
```

Expected: compile failure mentioning `initialProfile` or
`switchRemoteProfile` is undefined.

- [ ] **Step 3: RealControlDog 根据 observationType 创建模式**

先把最终 profile 生命周期加入 `RemoteControlMode`：

```dart
abstract interface class RemoteControlMode {
  void start();
  void updateProfile(RobotProfile profile);
  void updateVelocityBounds({
    required (double, double, double) minimum,
    required (double, double, double) maximum,
  });
  void dispose();
}
```

`LegacyRemoteMode.updateProfile` 只调用 Task 2 已测试的
`updateVelocityBounds`；`BodyHeightRemoteMode.updateProfile` 同时更新其
内部 `_legacy` 和体高积分器。

构造器新增显式参数：

```dart
required RobotProfile initialProfile,
```

增加 `_activeProfile` 与 `_remoteMode`。模式选择集中在一个方法：

```dart
void validateRemoteProfile(RobotProfile profile) {
  if (profile.observationType == 'bodyHeight') {
    if (controller is! BodyHeightAxisInput) {
      throw StateError(
        'bodyHeight remote mode requires BodyHeightAxisInput',
      );
    }
    validateBodyHeightRange(
      initialTarget: profile.bodyHeightCommand,
      minimum: profile.minBodyHeightCommand,
      maximum: profile.maxBodyHeightCommand,
    );
  }
}

void switchRemoteProfile(RobotProfile profile) {
  validateRemoteProfile(profile);
  final next = profile.observationType == 'bodyHeight'
      ? BodyHeightRemoteMode(context: _modeContext)
      : LegacyRemoteMode(
          context: _modeContext,
          velocityCommandMin: profile.velocityCommandMin,
          velocityCommandMax: profile.velocityCommandMax,
        );
  next.updateProfile(profile);

  final previous = _remoteMode;
  _remoteMode = null;
  previous?.dispose();

  try {
    next.start();
    _remoteMode = next;
    _activeProfile = profile;
  } catch (_) {
    next.dispose();
    rethrow;
  }
}
```

实现时必须先完成 profile/controller 能力校验和新模式配置，再释放旧模式。
若订阅启动仍异常，则立即 `arbiter.fault` 并向上抛出；构造阶段异常由顶层现有
清理路径禁用电机。

构造器顺序固定为：校验 `initialProfile` → 创建/配置/启动初始 mode →
绑定公共安全 subscriptions。这样非法 body-height profile 不会留下半初始化的
CH5/急停/profile subscriptions；任何已启动 mode 在后续构造步骤异常时都必须
由构造器 catch 块 `dispose()` 后再抛出。

R2 公共订阅增加精确保护：

```dart
if (_activeProfile.observationType == 'bodyHeight') {
  _log.warning(
    'R2 profile switch rejected for body-height policy; '
    'restart bodyheight_service.sh with h15 or h18',
  );
  return;
}
onProfileSwitch?.call();
```

这只改变 H15/H18 的不安全热切换；非体高策略继续调用现有 callback。

- [ ] **Step 4: ProfileManager 在修改 Brain 前验证，并在成功与 rollback 时同步遥控模式**

在 `switchTo` 完成同名 no-op 和目标查找后，先调用
`controlDog?.validateRemoteProfile(p)`；随后、修改 Brain 之前，拒绝任何进入或离开
`bodyHeight` profile 的运行时切换：

```dart
final current = currentProfile;
if (current.observationType == 'bodyHeight' ||
    p.observationType == 'bodyHeight') {
  throw StateError(
    'bodyHeight profiles require a service restart',
  );
}
```

同名 profile 的既有 no-op 判断必须先执行，因此查询当前 H15/H18 不会报错。此
保护同时覆盖 R2 和 gRPC `SwitchProfile`，防止固定 `Memory.historySize` 的
H15 58 维实例热换成 H18 580 维实例。

同时把 `toggle()` 的候选集合限制为 `observationType != "bodyHeight"`。
standard profile 的 R2 仍按原顺序循环所有 standard profile，但会跳过
H15/H18，避免异步 callback 把“需重启”的 `StateError` 变成未处理异常；活动
profile 为 body-height 时，前述 `RealControlDog` R2 保护会在调用
`toggle()` 前拒绝。

```dart
final keys = _profiles.entries
    .where((entry) => entry.value.observationType != 'bodyHeight')
    .map((entry) => entry.key)
    .toList(growable: false);
```

这样 Xbox/其他不提供体高轴的控制器会在任何模型、增益或状态变更前安全拒绝
body-height profile。

在 `_switchGains(RobotProfile profile)` 中，在增益和速度边界同步后调用：

```dart
controlDog?.switchRemoteProfile(profile);
```

由于 `switchTo` 的 catch 已用 `prevProfile` 调用 `_switchGains`，同一路径自动
恢复旧模式。测试必须验证成功和 rollback 两条路径，避免旧 mode 的 tick 或
subscription 残留。

- [ ] **Step 5: 所有构造点传入显式初始 profile**

在 `han_dog/bin/han_dog.dart` 的初始 YUNZHUO 和 Xbox 热插拔两个
`RealControlDog` 构造点都加入：

```dart
initialProfile: defaultProfile,
```

`han_dog/example/demo_full_controller.dart` 也是被 analyzer 检查的构造点。
将其现有姿态、模型路径和增益组合成一个 `observationType: "standard"` 的
`RobotProfile demoProfile`，并传入：

```dart
initialProfile: demoProfile,
```

在修改构造器前后分别运行：

```bash
rg -n "RealControlDog\\(" han_dog
```

Expected: 三个非测试构造点（YUNZHUO、Xbox hot-plug、demo）均明确传入
profile；测试辅助构造点也全部更新。

H15/H18 候选服务启动时均从 `HAN_DOG_DEFAULT_PROFILE` 选出的
`defaultProfile` 自动进入 `BodyHeightRemoteMode`；服务启动本身仍不发送
运动命令、不使能电机。

- [ ] **Step 6: 运行 profile、控制器与服务端回归**

```bash
dart format han_dog/lib/src/remote_control han_dog/lib/src/real_control_dog.dart han_dog/lib/src/app/profile_manager.dart han_dog/bin/han_dog.dart han_dog/example/demo_full_controller.dart han_dog/test/real_control_dog_test.dart han_dog/test/profile_manager_test.dart
dart test han_dog/test/real_control_dog_test.dart --reporter expanded
dart test han_dog/test/profile_manager_test.dart --reporter expanded
dart test han_dog/test/control_arbiter_test.dart --reporter expanded
dart test han_dog/test/unified_cms_server_test.dart --reporter expanded
```

Expected: all tests pass；现有 gRPC/遥控器仲裁优先级保持不变。

- [ ] **Step 7: 提交 profile 接线**

```bash
git add han_dog/lib/src/remote_control han_dog/lib/src/real_control_dog.dart han_dog/lib/src/app/profile_manager.dart han_dog/bin/han_dog.dart han_dog/example/demo_full_controller.dart han_dog/test/real_control_dog_test.dart han_dog/test/profile_manager_test.dart
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "feat(remote): select controller mode from profile"
```

## Task 6: 文档、静态检查和全量离线验收

**Files:**

- Modify: `README.md`
- Modify: `docs/BODYHEIGHTCTRL.md`
- Modify: `docs/superpowers/specs/2026-07-25-bodyheight-remote-mode-design.md`

- [ ] **Step 1: 更新公开按键和参数说明**

在 `README.md` 和 `docs/BODYHEIGHTCTRL.md` 写清：

- `standard` profile 使用旧遥控模式；
- H15/H18 自动使用 body-height 模式；
- 左摇杆 vx/vy、右摇杆 X yaw、右摇杆 Y 体高；
- 上推升高、下拉降低；
- 0.10 死区、0.08 m/s、50 Hz、100 ms 最大时间步；
- H15/H18 当前范围 0.20–0.54 m、默认 0.35 m；
- Standing 首次输入会进入 `Walking(0,0,0)`；
- 回中保持 Walking 和当前体高，R1 回 Standing 后复位 0.35 m；
- 物理遥控器期间 gRPC 命令仍受仲裁器拒绝；
- H15/H18 切换需 stop/start 服务，R2 不热切换；
- 启动服务不使能电机；使能后推动体高轴会产生真实运动。

把 README 中笼统的“R2 策略切换”和“支持所有 profile 热切换”改成按模式区分，
避免文档与安全行为冲突。

- [ ] **Step 2: 在设计文档记录最终文件结构和 100 ms 限幅**

只补充实现落点和已确认常量，不重写已批准需求：

```text
RealControlDog
  ├─ LegacyRemoteMode
  └─ BodyHeightRemoteMode
       ├─ LegacyRemoteMode (shared motion bindings)
       └─ BodyHeightIntegrator
```

- [ ] **Step 3: 格式化和静态分析**

Run:

```bash
dart format --output=none --set-exit-if-changed han_dog/lib han_dog/test han_dog/bin
dart analyze han_dog
```

Expected: formatter exit 0；analyzer reports no errors or warnings introduced by
this change.

- [ ] **Step 4: 运行 Dart 离线测试**

Run:

```bash
dart test han_dog/test --reporter expanded
dart test han_dog_brain/test --reporter expanded
```

Expected: all tests pass；未设置 ONNX 环境变量时两个 ONNX smoke tests 明确
显示 skipped，而不是 failed。

- [ ] **Step 5: 在已有模型文件的机器人上只跑 ONNX smoke**

此步骤只加载模型并以 mock 传感器推理，不启动 `han_dog.dart`，不会打开硬件或
使机器人运动：

```bash
export THUNDER_H15_ONNX=/home/bsrl1/brainstem-bodyheightctrl/model/thunder_h15_model10400.onnx
export THUNDER_H18_ONNX=/home/bsrl1/brainstem-bodyheightctrl/model/thunder_h18_model5000.onnx
/home/bsrl1/flutter/bin/dart test han_dog_brain/test/body_height_onnx_smoke_test.dart --reporter expanded
```

Expected:

```text
H15 loads policy_obs [batch,58] and performs finite inference
H18 loads policy_history [batch,580] and performs finite inference
All tests passed!
```

- [ ] **Step 6: 运行既有 Python/Bash 工具回归**

```bash
python -m unittest discover -s scripts/tests -p "test_bodyheight_grpc.py" -v
python -m py_compile scripts/bodyheight_grpc.py scripts/tests/test_bodyheight_grpc.py
bash -n scripts/bodyheight_service.sh
bash scripts/tests/bodyheight_service_test.sh
```

Expected: Python tests pass，`py_compile`/`bash -n` exit 0，服务脚本 fake
测试通过；若 Windows MSYS 在 Bash 解析前失败，记录为环境限制，并在机器人
Linux 上补跑相同 Bash 命令后才能宣称该项通过。

- [ ] **Step 7: 做变更范围和危险调用审计**

Run:

```bash
git diff --check
git status --short
rg -n "joint\.enable|sendAction|SerialPortController|RealJoint\(" han_dog/test/remote_control_mode_test.dart han_dog/test/body_height_integrator_test.dart
rg -n "A\.setBodyHeight" han_dog/lib/src/remote_control
```

Expected:

- `git diff --check` 无输出；
- 新测试中不存在真实设备/电机调用；
- `A.setBodyHeight` 只出现在通过 `RemoteControlModeContext.sendCommand`
  进入 `ControlArbiter` 的体高模式路径；
- 工作树只包含本计划列出的文件和已知、无关的本地未跟踪测试临时目录。

- [ ] **Step 8: 提交文档和最终验证记录**

```bash
git add README.md docs/BODYHEIGHTCTRL.md docs/superpowers/specs/2026-07-25-bodyheight-remote-mode-design.md
git -c user.name=hahadahe -c user.email=911987281@qq.com commit -m "docs(bodyheight): document remote height controls"
```

## 完成标准

- H15/H18 均由活动 profile 自动选择 `BodyHeightRemoteMode`。
- 非 body-height profile 只创建 `LegacyRemoteMode`，且旧回归全部通过。
- 右摇杆上/下以 0.08 m/s、0.10 死区、50 Hz、最大 100 ms 时间步调节体高。
- Standing 只触发一次 `Walk.zero`；Walking 中体高更新不覆盖左摇杆速度。
- Grounded/Zero/Transitioning 不响应体高轴。
- R1 到 Standing 后复位 profile 默认体高；回中保持 Walking 和当前体高。
- 150 ms 遥控器 watchdog、profile 切换和 dispose 均停止旧积分/订阅。
- CH5、红键、低压保护、校零、CAN 映射和 gRPC 仲裁代码没有行为退化。
- 所有自动测试离线通过；没有执行实机使能、站立、行走或体高运动。
- 各提交使用 `hahadahe <911987281@qq.com>`，不修改默认 Git 身份。
