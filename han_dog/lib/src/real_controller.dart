import 'dart:async';
import 'dart:typed_data';

import 'package:frequency_watch/frequency_watch.dart';
import 'package:logging/logging.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vector_math/vector_math.dart';

import 'gamepad.dart';
import 'yunzhuo_control_mode.dart';

final _log = Logger('han_dog.controller');

/// Latched switches: establish an enabled baseline, then accept either new edge.
Stream<bool> enabledButtonChanges(
  Stream<YunZhuoState> input,
  bool Function(YunZhuoState) button, {
  required bool Function() allowed,
  required int Function() generation,
  DateTime Function() clock = processMonotonicNow,
}) {
  bool? baseline;
  int? previousGeneration;
  DateTime? previousFrame;
  return input
      .where((state) {
        final now = clock();
        final currentGeneration = generation();
        final gap = previousFrame == null
            ? null
            : now.difference(previousFrame!);
        if (currentGeneration != previousGeneration ||
            (gap != null &&
                (gap.isNegative || gap >= const Duration(milliseconds: 150)))) {
          baseline = null;
        }
        previousGeneration = currentGeneration;
        previousFrame = now;
        if (!state.H || !allowed()) {
          baseline = null;
          return false;
        }
        final previous = baseline;
        baseline = button(state);
        return previous != null && baseline != previous;
      })
      .map((_) => true);
}

Stream<bool> enabledStandUpPresses(
  Stream<YunZhuoState> input, {
  required bool Function() allowed,
  required int Function() generation,
  DateTime Function() clock = processMonotonicNow,
}) => enabledButtonChanges(
  input,
  (s) => s.L1,
  allowed: allowed,
  generation: generation,
  clock: clock,
);

Stream<bool> safeEnableRequests(Stream<bool> input) =>
    Stream<bool>.multi((output) {
      var sawLow = false;
      Timer? timeout;
      final subscription = input.listen(
        (high) {
          timeout?.cancel();
          if (!high) sawLow = true;
          output.addSync(high && sawLow);
          timeout = Timer(const Duration(milliseconds: 150), () {
            sawLow = false;
            output.addSync(false);
          });
        },
        onError: (Object error, StackTrace st) {
          sawLow = false;
          timeout?.cancel();
          output.addSync(false);
          output.addErrorSync(error, st);
        },
        onDone: () {
          timeout?.cancel();
          output.addSync(false);
          output.closeSync();
        },
      );
      output.onCancel = () {
        timeout?.cancel();
        return subscription.cancel();
      };
    }, isBroadcast: input.isBroadcast).distinct();

Stream<Vector3> enabledDirection(
  Stream<YunZhuoState> input,
  String observationType, {
  bool Function()? allowed,
  int Function()? generation,
}) {
  var armed = false;
  int? previousGeneration;
  DateTime? previousFrame;
  return input.map((data) {
    final now = DateTime.now();
    final currentGeneration = generation?.call();
    if (currentGeneration != previousGeneration ||
        (previousFrame != null &&
            now.difference(previousFrame!).inMilliseconds > 150)) {
      armed = false;
    }
    previousGeneration = currentGeneration;
    previousFrame = now;
    if (!data.H || allowed?.call() == false) {
      armed = false;
      return Vector3.zero();
    }
    final scale = data.LT ? 0.5 : (data.RT ? 1.5 : 1.0);
    final yaw = (data.knob + data.rightStick.x * 0.5).clamp(-1.0, 1.0);
    final value = Vector3(
      data.leftStick.y * scale,
      -data.leftStick.x * scale,
      -yaw,
    );
    if (value.x.abs() < .02 && value.y.abs() < .02 && value.z.abs() < .02) {
      armed = true;
    }
    return armed ? value : Vector3.zero();
  });
}

Stream<Iterable<YunZhuoState>> _decodeStandardSbus(Stream<Uint8List> stream) =>
    const StandardSbusChannelDecoder()
        .bind(stream)
        .map(
          (frames) => frames
              .where((frame) => isStandardSbusHealthy(frame.$2))
              .map((frame) => YunZhuoState.fromChannels(frame.$1, frame.$2)),
        );

class RealController implements Gamepad, HardStopGamepad, InputHealthGamepad {
  final String portName;
  final DateTime Function() _clock;
  late SerialPortController<Never, YunZhuoState> port;
  final hz = RealFrequency();

  // 稳定的桥接流：下游订阅者不受断连/重连影响
  final _stateController = StreamController<YunZhuoState>.broadcast();
  final _hardStopController = StreamController<void>.broadcast();
  StreamSubscription<Iterable<YunZhuoState>>? _portSub;
  Timer? _inputWatchdog;
  final _modeStateMachine = YunZhuoModeStateMachine();
  late final Stream<YunZhuoControlFrame> controlFrameStream;

  /// 进入 arm 模式前由上层注入的机器狗 FSM 条件。
  /// 未注入时拒绝进入 arm；dog/neutral 不受影响。
  bool Function()? armModeAdmission;

  Stream<YunZhuoState> get stateStream => _stateController.stream;
  bool _standUpEnabled = false;
  int _standUpGeneration = 0;
  bool _opened = false;
  DateTime? _lastInputAt;
  bool _hardStopActive = true;

  @override
  bool get hardStopActive =>
      _hardStopActive ||
      !_opened ||
      _disposed ||
      _lastInputAt == null ||
      _clock().difference(_lastInputAt!).abs() >=
          const Duration(milliseconds: 150);

  @override
  bool get inputHealthy =>
      _opened &&
      !_disposed &&
      _lastInputAt != null &&
      _clock().difference(_lastInputAt!).abs() <=
          const Duration(milliseconds: 500);

  @override
  int get inputHz => hz.value;

  void setStandUpEnabled(bool enabled) {
    _standUpEnabled = enabled;
    ++_standUpGeneration;
  }

  @override
  Stream<void> get hardStop => _hardStopController.stream;

  /// 经 CH5/G_S 消抖和安全门槛处理后的完整云卓控制帧。
  ///
  /// 该流由 [stateStream] 单次派生并共享，机械臂桥接必须订阅这里或
  /// [stateStream]，不能再次打开 `/dev/yunzhuo`。
  Stream<YunZhuoModeSnapshot> get modeStream =>
      controlFrameStream.map((frame) => frame.mode);

  // CH1  右摇杆左右 (rightStick.x) → 叠加到旋转轴（yaw 精细控制）
  // CH2  右摇杆上下 (rightStick.y) → 保留，待步态/姿态扩展
  // CH8  LT 两档    → 精确模式（速度 × 0.5）
  // CH12 RT 两档    → 冲刺模式（速度 × 1.5）
  // CH16 R2 两档    → 策略切换

  /// 行走方向流：(x=前后, y=左右, z=旋转)，与 Walk RPC / RL 训练约定一致。
  ///
  /// 训练约定：x>0 前进, y>0 向左, z>0 逆时针。
  /// 摇杆约定：leftStick.y>0 前推, leftStick.x>0 右推, knob>0 顺时针。
  /// 速度缩放规则：LT=精确(0.5×)，RT=冲刺(1.5×)，默认 1.0×。
  /// rightStick.x 以 0.5 权重叠加到旋转轴，恢复 GitHub 存档中的机器狗专用控制。
  /// CH5 不再选择 dog/neutral/arm，不影响机器狗控制。
  /// 行走方向流，强关联遥控器：有数据就输出，150ms 无数据直接归零。
  @override
  Stream<Vector3> get direction => watchdogDecay(
    enabledDirection(
      stateStream,
      'standard',
      allowed: () => _standUpEnabled,
      generation: () => _standUpGeneration,
    ),
    timeout: const Duration(milliseconds: 150),
    steps: 1, // 1 步直接归零，不衰减
    stepPeriod: const Duration(milliseconds: 1),
    decayCurve: (s0, t) => s0 * 0.0, // 直接到 0
  );

  @override
  Stream<bool> get standup => enabledStandUpPresses(
    stateStream,
    allowed: () => _standUpEnabled,
    generation: () => _standUpGeneration,
    clock: _clock,
  );
  @override
  Stream<bool> get sitdown => enabledButtonChanges(
    stateStream,
    (s) => s.L2,
    allowed: () => _standUpEnabled,
    generation: () => _standUpGeneration,
    clock: _clock,
  );
  @override
  Stream<bool> get idle => enabledButtonChanges(
    stateStream,
    (s) => s.R1,
    allowed: () => _standUpEnabled,
    generation: () => _standUpGeneration,
    clock: _clock,
  );

  @override
  Stream<bool> get red =>
      redButtonPressEvents(stateStream.map((data) => data.red));

  @override
  Stream<bool> get enabled =>
      safeEnableRequests(stateStream.map((data) => data.H));

  /// 策略切换：R2 (CH16) 状态变更触发
  @override
  Stream<void> get switchProfile => stateStream
      .map((data) => data.rawChannels[15])
      .distinct()
      .pairwise()
      .where((p) => p[0] != p[1])
      .map((_) {});

  /// 标零组合键：CH5(channels[4]) 高档 + CH9(channels[8]) 状态切换 + CH10(channels[9]) 状态切换
  /// CH9/CH10 发生切换的瞬间触发一次（不要求高/低，只要求变更）
  @override
  Stream<void> get calibrate => stateStream
      .pairwise()
      .where((p) {
        final previous = p[0];
        final current = p[1];
        final ch5High = current.rawChannels[4] == SbusValues.high;
        final ch9Changed = previous.rawChannels[8] != current.rawChannels[8];
        final ch10Changed = previous.rawChannels[9] != current.rawChannels[9];
        return ch5High && ch9Changed && ch10Changed;
      })
      .map((_) {});

  RealController([this.portName = '/dev/ttyUSB0', DateTime Function()? clock])
    : _clock = clock ?? processMonotonicNow {
    _modeStateMachine.armAdmission = () => armModeAdmission?.call() ?? false;
    controlFrameStream = stateStream
        .map((state) {
          final now = _clock();
          return YunZhuoControlFrame(
            state: state,
            mode: _modeStateMachine.update(state, now),
            receivedAt: now,
          );
        })
        .shareReplay(maxSize: 1);
    port = SerialPortController<Never, YunZhuoState>(
      portName,
      baudRate: 100000,
      parity: .ParityEven,
      stopbits: .StopTwo,
      stateDecoder: _decodeStandardSbus,
    );
  }

  bool open() {
    if (!port.open()) {
      _opened = false;
      _log.severe('Controller open failed: $portName');
      return false;
    }
    _listen();
    _opened = true;
    _log.info('Controller opened: $portName');
    return true;
  }

  /// 断连后尝试重新打开串口，数据自动流入已有的 stateStream。
  /// 新建 SerialPortController，避免原 port.state 单次订阅导致的 "Stream has already been listened to"。
  Future<bool> reopen() async {
    _log.info('Controller reopening: $portName');
    final previousSub = _portSub;
    _portSub = null;
    await previousSub?.cancel();
    try {
      port.close();
      port.dispose();
    } catch (e, st) {
      _log.warning('Error closing port during reopen: $portName', e, st);
    }
    port = SerialPortController<Never, YunZhuoState>(
      portName,
      baudRate: 100000,
      parity: .ParityEven,
      stopbits: .StopTwo,
      stateDecoder: _decodeStandardSbus,
    );
    if (!port.open()) {
      _opened = false;
      _log.severe('Controller reopen failed: $portName');
      return false;
    }
    _listen();
    _opened = true;
    _log.info('Controller reopened: $portName');
    return true;
  }

  void _listen() {
    _portSub?.cancel();
    _portSub = port.state.listen(
      (batch) {
        if (_disposed) return;
        if (batch.isNotEmpty) _lastInputAt = _clock();
        hz.add(batch.length);
        for (final s in batch) {
          _hardStopActive = false; // 真实输入恢复；自动补出的零指令不经过这里。
          _resetInputWatchdog();
          _stateController.add(s);
        }
      },
      onError: (Object error, StackTrace st) {
        _log.severe('Port stream error', error, st);
        // 向下游广播错误，使 RealControlDog 等订阅者触发 Fault。
        // broadcast stream 不会因 addError 终止，reopen() 仍可恢复。
        if (!_disposed) {
          _emitHardStop();
          _stateController.addError(error, st);
        }
      },
      onDone: () {
        _opened = false;
        _log.warning('Port stream closed unexpectedly');
        _emitHardStop();
      },
    );
  }

  void _resetInputWatchdog() {
    _inputWatchdog?.cancel();
    _inputWatchdog = Timer(const Duration(milliseconds: 150), _emitHardStop);
  }

  void _emitHardStop() {
    _hardStopActive = true;
    if (!_disposed && !_hardStopController.isClosed) {
      _modeStateMachine.resetForInputLoss();
      _hardStopController.add(null);
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _opened = false;
    _inputWatchdog?.cancel();
    _log.info('Controller disposing: $portName');
    _portSub?.cancel();
    _stateController.close();
    _hardStopController.close();
    port.dispose();
  }
}

/// 将红键电平转换为按下事件：启动首帧已按下也触发，松开不触发。
Stream<bool> redButtonPressEvents(Stream<bool> states) async* {
  bool? previous;
  await for (final pressed in states) {
    if (pressed && previous != true) yield true;
    previous = pressed;
  }
}

T _defaultDecayCurve<T>(T s0, double t) => s0;

/// 纯函数：输入控制流 -> 输出"超时后衰减到 0"的控制流
Stream<T> watchdogDecay<T>(
  Stream<T> control$, {
  Duration timeout = const Duration(milliseconds: 50),
  int steps = 20,
  Duration stepPeriod = const Duration(milliseconds: 100),
  T Function(T, double)? decayCurve,
}) {
  assert(steps > 0);
  decayCurve ??= _defaultDecayCurve;

  Stream<T> decayFrom(T start) {
    // 每 stepPeriod 输出一次，共 steps 次：start*(steps-1)/steps ... 0
    return Stream<int>.periodic(stepPeriod, (i) => i).take(steps).map((i) {
      final k = (steps - 1 - i) / steps; // 0.9 ... 0
      return decayCurve!(start, k);
    });
  }

  return control$.switchMap(
    (cmd) => Rx.concat<T>([
      Stream.value(cmd), // 立刻输出
      Stream<void>.value(null).delay(timeout).switchMap((_) => decayFrom(cmd)),
    ]),
  );
}
