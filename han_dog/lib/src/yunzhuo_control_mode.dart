import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:vector_math/vector_math.dart';

final Stopwatch _processMonotonicStopwatch = Stopwatch()..start();

/// 同一进程共享的单调时钟；仅用于安全超时和控制状态机，不用于日志时间。
DateTime processMonotonicNow() => DateTime.fromMicrosecondsSinceEpoch(
  _processMonotonicStopwatch.elapsedMicroseconds,
  isUtc: true,
);

/// 云卓 G/S 三档所选择的有效控制域。
///
/// 冷启动及断流恢复时固定为 [neutral]。进入 dog/arm 前，必须在四轴
/// 居中的前提下，将 G/S 中档稳定保持 [neutralGateDuration]；快速扫档
/// 不会获得控制权。
enum YunZhuoControlMode { dog, neutral, arm }

class YunZhuoModeSnapshot {
  final YunZhuoControlMode mode;

  /// 机器狗方向命令的线性倍率。
  ///
  /// 从 dog 切出时 400 ms 降为 0；取消切换返回 dog 时 200 ms 恢复。
  final double dogDriveScale;
  final bool neutralGateReady;
  final bool modeChanged;

  const YunZhuoModeSnapshot({
    required this.mode,
    required this.dogDriveScale,
    required this.neutralGateReady,
    required this.modeChanged,
  });
}

class YunZhuoControlFrame {
  final YunZhuoState state;
  final YunZhuoModeSnapshot mode;

  /// [processMonotonicNow] 时间域中的接收时刻，不是墙上时间。
  final DateTime receivedAt;

  const YunZhuoControlFrame({
    required this.state,
    required this.mode,
    required this.receivedAt,
  });
}

/// CH5/G_S 模式切换状态机。
///
/// 规则：
/// - 所有档位先做 100 ms 消抖；arm 一旦离档则不等待消抖，立即 HOLD。
/// - 中档且四轴连续居中 300 ms 才打开下一次选档门槛。
/// - dog -> neutral 使用 400 ms 线性减速。
/// - dog 切换尚未完成时返回 dog，使用 200 ms 线性恢复。
/// - 冷启动和断流恢复都必须重新经过居中中档门槛。
class YunZhuoModeStateMachine {
  final Duration debounceDuration;
  final Duration neutralGateDuration;
  final Duration dogRampDownDuration;
  final Duration dogRampUpDuration;
  final double stickDeadzone;

  /// 由上层注入机器狗 FSM 准入条件；返回 false 时消费本次中档门槛并保持中立。
  bool Function()? armAdmission;

  YunZhuoControlMode _mode = YunZhuoControlMode.neutral;
  YunZhuoControlMode? _modeBeforeNeutral;
  GSState? _candidate;
  DateTime? _candidateSince;
  DateTime? _neutralCenteredSince;
  bool _neutralGateReady = false;
  DateTime? _lastUpdateAt;

  double _rampStart = 0.0;
  double _rampTarget = 0.0;
  DateTime? _rampStartedAt;
  Duration _rampDuration = Duration.zero;

  YunZhuoModeStateMachine({
    this.debounceDuration = const Duration(milliseconds: 100),
    this.neutralGateDuration = const Duration(milliseconds: 300),
    this.dogRampDownDuration = const Duration(milliseconds: 400),
    this.dogRampUpDuration = const Duration(milliseconds: 200),
    this.stickDeadzone = 0.10,
  });

  YunZhuoControlMode get mode => _mode;
  bool get neutralGateReady => _neutralGateReady;

  /// 串口断流/看门狗触发后清除所有物理档位历史，恢复必须重新走中档门槛。
  void resetForInputLoss() {
    _mode = YunZhuoControlMode.neutral;
    _modeBeforeNeutral = null;
    _candidate = null;
    _candidateSince = null;
    _neutralCenteredSince = null;
    _neutralGateReady = false;
    _lastUpdateAt = null;
    _rampStart = 0.0;
    _rampTarget = 0.0;
    _rampStartedAt = null;
    _rampDuration = Duration.zero;
  }

  YunZhuoModeSnapshot update(YunZhuoState state, DateTime now) {
    final previousUpdate = _lastUpdateAt;
    if (previousUpdate != null && now.isBefore(previousUpdate)) {
      // 注入时钟或平台异常回拨时 fail closed，不能冻结非零斜坡/档位。
      resetForInputLoss();
    }
    _lastUpdateAt = now;
    var changed = false;
    final detent = state.G_S;

    if (_candidate != detent) {
      _candidate = detent;
      _candidateSince = now;
    }

    final centered = areYunZhuoSticksCentered(state, stickDeadzone);
    if (detent == GSState.middle && centered) {
      _neutralCenteredSince ??= now;
    } else if (detent == GSState.middle) {
      _neutralCenteredSince = null;
      if (_neutralGateReady) _modeBeforeNeutral = null;
      _neutralGateReady = false;
    } else {
      // 离开中档后保留已经取得的门槛，直到目标档消抖完成并消费它。
      _neutralCenteredSince = null;
      if (_neutralGateReady && !centered) {
        // 带杆离开中档立即消费门槛；随后即使在消抖期间回中也不能入档。
        _neutralGateReady = false;
        _modeBeforeNeutral = null;
      }
    }

    // 离开机械臂物理档时优先安全：不等待触点消抖，立即撤销机械臂控制。
    if (_mode == YunZhuoControlMode.arm && detent != GSState.down) {
      _modeBeforeNeutral = YunZhuoControlMode.arm;
      _mode = YunZhuoControlMode.neutral;
      _neutralGateReady = false;
      _setRamp(now, 0.0, Duration.zero);
      changed = true;
    }

    final candidateStable =
        _candidateSince != null &&
        !now.difference(_candidateSince!).isNegative &&
        now.difference(_candidateSince!) >= debounceDuration;

    if (candidateStable) {
      switch (detent) {
        case GSState.middle:
          if (_mode != YunZhuoControlMode.neutral) {
            final oldMode = _mode;
            _modeBeforeNeutral = oldMode;
            _mode = YunZhuoControlMode.neutral;
            _neutralGateReady = false;
            if (oldMode == YunZhuoControlMode.dog) {
              _setRamp(now, 0.0, dogRampDownDuration);
            } else {
              _setRamp(now, 0.0, Duration.zero);
            }
            changed = true;
          }
          final centeredSince = _neutralCenteredSince;
          if (centeredSince != null &&
              now.difference(centeredSince) >= neutralGateDuration) {
            _neutralGateReady = true;
          }
          break;

        case GSState.up:
          if (_mode == YunZhuoControlMode.neutral) {
            final cancellingDogExit =
                _modeBeforeNeutral == YunZhuoControlMode.dog &&
                !_neutralGateReady &&
                _dogExitRampActive(now);
            final selectingAfterGate = _neutralGateReady;
            if (selectingAfterGate) {
              _neutralGateReady = false;
              _modeBeforeNeutral = null;
            }
            if ((selectingAfterGate && centered) || cancellingDogExit) {
              _mode = YunZhuoControlMode.dog;
              _modeBeforeNeutral = null;
              _setRamp(now, 1.0, dogRampUpDuration);
              changed = true;
            }
          } else if (_mode == YunZhuoControlMode.arm) {
            _modeBeforeNeutral = YunZhuoControlMode.arm;
            _mode = YunZhuoControlMode.neutral;
            _neutralGateReady = false;
            _setRamp(now, 0.0, Duration.zero);
            changed = true;
          }
          break;

        case GSState.down:
          if (_mode == YunZhuoControlMode.neutral && _neutralGateReady) {
            _neutralGateReady = false;
            _modeBeforeNeutral = null;
            final admitted = centered && (armAdmission?.call() ?? false);
            if (admitted) {
              _mode = YunZhuoControlMode.arm;
              _modeBeforeNeutral = null;
              _setRamp(now, 0.0, Duration.zero);
              changed = true;
            }
          } else if (_mode == YunZhuoControlMode.dog) {
            // 未经过稳定中档的快速扫档：只能进入逻辑中立。
            _modeBeforeNeutral = YunZhuoControlMode.dog;
            _mode = YunZhuoControlMode.neutral;
            _neutralGateReady = false;
            _setRamp(now, 0.0, dogRampDownDuration);
            changed = true;
          }
          break;
      }
    }

    return YunZhuoModeSnapshot(
      mode: _mode,
      dogDriveScale: _scaleAt(now),
      neutralGateReady: _neutralGateReady,
      modeChanged: changed,
    );
  }

  void _setRamp(DateTime now, double target, Duration duration) {
    final current = _scaleAt(now);
    _rampStart = current;
    _rampTarget = target;
    _rampStartedAt = now;
    _rampDuration = duration;
    if (duration == Duration.zero) {
      _rampStart = target;
    }
  }

  bool _dogExitRampActive(DateTime now) {
    final startedAt = _rampStartedAt;
    if (startedAt == null ||
        _rampTarget != 0.0 ||
        _rampDuration != dogRampDownDuration ||
        _rampDuration == Duration.zero) {
      return false;
    }
    final elapsed = now.difference(startedAt);
    return !elapsed.isNegative && elapsed < _rampDuration;
  }

  double _scaleAt(DateTime now) {
    final startedAt = _rampStartedAt;
    if (startedAt == null || _rampDuration == Duration.zero) {
      return _rampTarget;
    }
    final elapsedUs = now.difference(startedAt).inMicroseconds;
    if (elapsedUs < 0) return _rampTarget == 0.0 ? 0.0 : _rampStart;
    if (elapsedUs == 0) return _rampStart;
    final durationUs = _rampDuration.inMicroseconds;
    if (elapsedUs >= durationUs) return _rampTarget;
    final t = elapsedUs / durationUs;
    return _rampStart + (_rampTarget - _rampStart) * t;
  }
}

bool areYunZhuoSticksCentered(YunZhuoState state, [double deadzone = 0.10]) {
  return state.leftStick.x.abs() <= deadzone &&
      state.leftStick.y.abs() <= deadzone &&
      state.rightStick.x.abs() <= deadzone &&
      state.rightStick.y.abs() <= deadzone;
}

/// 将云卓输入映射为机器狗方向。右摇杆不参与偏航，偏航只来自 CH14 旋钮。
Vector3 mapYunZhuoDogDirection(YunZhuoState state, {double driveScale = 1.0}) {
  final speedScale = state.LT ? 0.5 : (state.RT ? 1.5 : 1.0);
  final modeScale = driveScale.clamp(0.0, 1.0);
  final translationScale = speedScale * modeScale;
  return Vector3(
    state.leftStick.y * translationScale,
    -state.leftStick.x * translationScale,
    -state.knob.clamp(-1.0, 1.0) * modeScale,
  );
}
