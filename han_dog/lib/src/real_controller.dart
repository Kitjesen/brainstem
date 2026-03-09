import 'dart:async';

import 'package:frequency_watch/frequency_watch.dart';
import 'package:logging/logging.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vector_math/vector_math.dart';

final _log = Logger('han_dog.controller');

class RealController {
  final String portName;
  late SerialPortController<Never, YunZhuoState> port;
  final hz = RealFrequency();

  // 稳定的桥接流：下游订阅者不受断连/重连影响
  final _stateController = StreamController<YunZhuoState>.broadcast();
  StreamSubscription<Iterable<YunZhuoState>>? _portSub;

  Stream<YunZhuoState> get stateStream => _stateController.stream;

  // CH1  右摇杆左右 (rightStick.x) → 叠加到旋转轴（yaw 精细控制）
  // CH2  右摇杆上下 (rightStick.y) → 保留，待步态/姿态扩展
  // CH8  LT 两档    → 精确模式（速度 × 0.5）
  // CH12 RT 两档    → 冲刺模式（速度 × 1.5）
  // CH16 R2 两档    → 策略切换

  /// 行走方向流：(x=侧移, y=前进, z=旋转)。
  ///
  /// 速度缩放规则：LT=精确(0.5×)，RT=冲刺(1.5×)，默认 1.0×。
  /// rightStick.x 以 0.5 权重叠加到旋转轴，实现双手协同偏航控制。
  Stream<Vector3> get direction => watchdogDecay(
    stateStream.map((data) {
      final scale = data.LT ? 0.5 : (data.RT ? 1.5 : 1.0);
      final yaw = (data.knob + data.rightStick.x * 0.5).clamp(-1.0, 1.0);
      return Vector3(
        data.leftStick.x * scale,
        data.leftStick.y * scale,
        yaw,
      );
    }),
    timeout: const Duration(milliseconds: 50),
    steps: 100,
    stepPeriod: const Duration(milliseconds: 20),
    decayCurve: (s0, t) => s0 * t,
  );

  Stream<bool> get standup => stateStream
      .map((data) => data.L1)
      .distinct()
      .pairwise()
      .map((p) => p[0] != p[1]);
  Stream<bool> get sitdown => stateStream
      .map((data) => data.L2)
      .distinct()
      .pairwise()
      .map((p) => p[0] != p[1]);
  Stream<bool> get idle => stateStream
      .map((data) => data.R1)
      .distinct()
      .pairwise()
      .map((p) => p[0] != p[1]);

  Stream<bool> get red => stateStream
      .map((data) => data.red)
      .distinct()
      .pairwise()
      .map((p) => p[0] != p[1]);

  Stream<bool> get enabled => stateStream.map((data) => data.H).distinct();

  /// 策略切换：R2 (CH16) 状态变更触发
  Stream<void> get switchProfile => stateStream
      .map((data) => data.rawChannels[15])
      .distinct()
      .pairwise()
      .where((p) => p[0] != p[1])
      .map((_) {});

  /// 标零组合键：CH5(channels[4]) 高档 + CH9(channels[8]) 状态切换 + CH10(channels[9]) 状态切换
  /// CH9/CH10 发生切换的瞬间触发一次（不要求高/低，只要求变更）
  Stream<void> get calibrate => stateStream
      .pairwise()
      .where((p) {
        final prev = p[0];
        final curr = p[1];
        final ch5High = curr.rawChannels[4] == SbusValues.high;
        final ch9Changed = prev.rawChannels[8] != curr.rawChannels[8];
        final ch10Changed = prev.rawChannels[9] != curr.rawChannels[9];
        return ch5High && ch9Changed && ch10Changed;
      })
      .map((_) {});

  RealController([this.portName = '/dev/ttyUSB0']) {
    port = SerialPortController<Never, YunZhuoState>(portName);
  }

  bool open() {
    if (!port.open()) {
      _log.severe('Controller open failed: $portName');
      return false;
    }
    _listen();
    _log.info('Controller opened: $portName');
    return true;
  }

  /// 断连后尝试重新打开串口，数据自动流入已有的 stateStream。
  /// 新建 SerialPortController，避免原 port.state 单次订阅导致的 "Stream has already been listened to"。
  bool reopen() {
    _log.info('Controller reopening: $portName');
    _portSub?.cancel();
    try {
      port.close();
      port.dispose();
    } catch (e, st) {
      _log.warning('Error closing port during reopen: $portName', e, st);
    }
    port = SerialPortController<Never, YunZhuoState>(portName);
    if (!port.open()) {
      _log.severe('Controller reopen failed: $portName');
      return false;
    }
    _listen();
    _log.info('Controller reopened: $portName');
    return true;
  }

  void _listen() {
    _portSub?.cancel();
    _portSub = port.state.listen(
      (batch) {
        if (_disposed) return;
        hz.add(batch.length);
        for (final s in batch) {
          _stateController.add(s);
        }
      },
      onError: (Object error, StackTrace st) {
        _log.severe('Port stream error', error, st);
      },
      onDone: () {
        _log.info('Port stream closed');
      },
    );
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _log.info('Controller disposing: $portName');
    _portSub?.cancel();
    _stateController.close();
    port.dispose();
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
