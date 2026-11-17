// YUNZHUO 遥控器驱动桥接：将摇杆信号转换为 FSM 动作（Walk/StandUp/SitDown/Idle）。

import 'dart:async';

import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

final _log = Logger('thunder.control');

/// Maps a signed stick input through a deadzone into a bounded command.
/// Inputs outside [-1, 1] are saturated before mapping; this also keeps the
/// optional YUNZHUO RT 1.5x sprint mode inside the active profile envelope.
double shapeSignedCommand(
  double raw, {
  required double deadzone,
  required double minCommand,
  required double maxCommand,
}) {
  final magnitude = raw.abs().clamp(0.0, 1.0).toDouble();
  if (magnitude <= deadzone) return 0.0;
  final normalized =
      minCommand +
      (magnitude - deadzone) / (1.0 - deadzone) * (1.0 - minCommand);
  final command = normalized * maxCommand;
  return raw.isNegative ? -command : command;
}

/// Limits normal operator velocity changes before they reach the policy.
///
/// Emergency stops bypass this limiter. A reversal always decelerates to zero
/// before accelerating in the opposite direction, and a delayed event-loop
/// iteration cannot create a large catch-up step.
class DogCommandRateLimiter {
  final double forwardAcceleration;
  final double forwardDeceleration;
  final double lateralAcceleration;
  final double lateralDeceleration;
  final double yawAcceleration;
  final double yawDeceleration;
  final Duration maximumStepDuration;

  Vector3 _value = Vector3.zero();
  DateTime? _lastUpdateAt;

  DogCommandRateLimiter({
    this.forwardAcceleration = 2.0,
    this.forwardDeceleration = 3.0,
    this.lateralAcceleration = 1.5,
    this.lateralDeceleration = 2.5,
    this.yawAcceleration = 1.2,
    this.yawDeceleration = 2.5,
    this.maximumStepDuration = const Duration(milliseconds: 30),
  });

  Vector3 get value => Vector3.copy(_value);

  void reset() {
    _value = Vector3.zero();
    _lastUpdateAt = null;
  }

  Vector3 limit(Vector3 target, DateTime now) {
    final previousUpdate = _lastUpdateAt;
    _lastUpdateAt = now;
    if (previousUpdate == null) return value;

    final elapsedUs = now.difference(previousUpdate).inMicroseconds;
    if (elapsedUs <= 0) {
      reset();
      _lastUpdateAt = now;
      return value;
    }
    final boundedUs = elapsedUs.clamp(0, maximumStepDuration.inMicroseconds);
    final dt = boundedUs / Duration.microsecondsPerSecond;
    _value = Vector3(
      _limitAxis(
        _value.x,
        target.x,
        forwardAcceleration,
        forwardDeceleration,
        dt,
      ),
      _limitAxis(
        _value.y,
        target.y,
        lateralAcceleration,
        lateralDeceleration,
        dt,
      ),
      _limitAxis(_value.z, target.z, yawAcceleration, yawDeceleration, dt),
    );
    return value;
  }

  static double _limitAxis(
    double current,
    double target,
    double acceleration,
    double deceleration,
    double dt,
  ) {
    if (current == target) return target;
    if (current != 0 && target != 0 && current.sign != target.sign) {
      return _moveTowards(current, 0, deceleration * dt);
    }
    final speedingUp = target.abs() > current.abs();
    return _moveTowards(
      current,
      target,
      (speedingUp ? acceleration : deceleration) * dt,
    );
  }

  static double _moveTowards(double current, double target, double maxDelta) {
    final delta = target - current;
    if (delta.abs() <= maxDelta) return target;
    return current + (delta.isNegative ? -maxDelta : maxDelta);
  }
}

class RealControlDog {
  final Brain brain;
  final ControlArbiter arbiter;
  final RealImu imu;
  final RealJoint joint;
  final Gamepad controller;
  final Future<void> Function()? requestMotorEnable;
  int _motorEnablePending = 0;

  bool get motorEnablePending => _motorEnablePending > 0;
  JointsMatrix inferKp;
  JointsMatrix inferKd;
  JointsMatrix standUpKp;
  JointsMatrix standUpKd;
  JointsMatrix sitDownKp;
  JointsMatrix sitDownKd;
  double commandVxMax;
  double commandVyMax;
  double commandYawMax;
  double forwardMinCommand;
  double lateralMinCommand;
  double yawMinCommand;

  /// 策略切换回调（由外部 ProfileManager 设置）。
  Future<void> Function()? onProfileSwitch;
  bool _profileSwitchInProgress = false;
  bool _l1StandingRequested = false;
  S? _profileSwitchState;
  int? _profileSwitchEnableGeneration;

  bool get canSwitchProfile {
    final state = arbiter.state;
    return !_disposed &&
        _standUpEnabled &&
        _operatorEnabled &&
        !arbiter.isHandlingEvent &&
        (!arbiter.profileSwitchInProgress || _profileSwitchInProgress) &&
        (state is Grounded || (state is Standing && _l1StandingRequested)) &&
        (_profileSwitchState == null ||
            identical(state, _profileSwitchState)) &&
        (_profileSwitchEnableGeneration == null ||
            _profileSwitchEnableGeneration == _standUpEnableGeneration) &&
        _controllerCommandIsZero &&
        !(controller is HardStopGamepad &&
            (controller as HardStopGamepad).hardStopActive);
  }

  /// 电机使能状态变化回调（由外部设置，用于同步 motorOutputEnabled 标志）。
  void Function(bool enabled)? onMotorEnableChanged;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  static const double _forwardDeadzone = 0.10;
  static const double _yawDeadzone = 0.10;
  static const double _lateralDeadzone = 0.10;
  static const double _standUpWheelSpeedMax = 0.5;
  static const double _standUpGyroMax = 0.15;
  static const Duration _standUpSettlePoll = Duration(milliseconds: 50);
  static const Duration _standUpSettleDuration = Duration(milliseconds: 300);
  static const Duration _standUpSettleTimeout = Duration(seconds: 2);

  Vector3 _latestControllerCommand = Vector3.zero();
  Timer? _standUpSettleTimer;
  Vector3 _lastWalkCommand = Vector3.zero();
  final DateTime Function() commandClock;
  bool _operatorEnabled = true;
  bool _standUpEnabled = false;
  int _standUpEnableGeneration = 0;
  final DogCommandRateLimiter _walkCommandLimiter = DogCommandRateLimiter(
    forwardAcceleration: 0.5,
    forwardDeceleration: 2.5,
    lateralAcceleration: 0.5,
    lateralDeceleration: 2.5,
    yawAcceleration: 0.5,
    yawDeceleration: 2.5,
  );

  double _mapForward(double rawVx) => shapeSignedCommand(
    rawVx,
    deadzone: _forwardDeadzone,
    minCommand: forwardMinCommand,
    maxCommand: commandVxMax,
  );

  double _mapYaw(double rawYaw) => shapeSignedCommand(
    rawYaw,
    deadzone: _yawDeadzone,
    minCommand: yawMinCommand,
    maxCommand: commandYawMax,
  );

  double _mapLateral(double rawVy) => shapeSignedCommand(
    rawVy,
    deadzone: _lateralDeadzone,
    minCommand: lateralMinCommand,
    maxCommand: commandVyMax,
  );

  RealControlDog({
    required this.brain,
    required this.imu,
    required this.joint,
    required this.arbiter,
    required this.inferKp,
    required this.inferKd,
    required this.standUpKp,
    required this.standUpKd,
    required this.sitDownKp,
    required this.sitDownKd,
    this.commandVxMax = 1.5,
    this.commandVyMax = 1.0,
    this.commandYawMax = 1.0,
    this.forwardMinCommand = 0.0,
    this.lateralMinCommand = 0.30,
    this.yawMinCommand = 0.40,
    this.commandClock = processMonotonicNow,
    required this.controller,
    this.requestMotorEnable,
  }) {
    _log.info(
      'COMMAND_RATE_LIMIT disabled: normal joystick commands are direct; '
      'command bounds, deadzones and emergency/watchdog stops retained',
    );
    // 监听 CMS 状态变化，自动设置对应的 kp/kd
    _subscriptions.add(
      arbiter.stateStream.listen(
        (state) {
          if (state is Grounded ||
              state is Zero ||
              (state is Transitioning && state.target is! StandUpCommand)) {
            _l1StandingRequested = false;
          }
          if (state is! Walking) {
            _cancelPendingStandUp();
            _walkCommandLimiter.reset();
            _lastWalkCommand = Vector3.zero();
          }
          switch (state) {
            case Walking():
              joint.kpExt = applyThunderWalkingHipKp(inferKp);
              joint.kdExt = applyThunderWalkingHipKdScale(inferKd);
            case Transitioning(:final target):
              if (target is StandUpCommand) {
                joint.kpExt = standUpKp;
                joint.kdExt = standUpKd;
              } else {
                joint.kpExt = sitDownKp;
                joint.kdExt = sitDownKd;
              }
            case Standing() || Grounded() || Zero():
              break;
          }
        },
        onError: (Object error, StackTrace st) {
          _log.severe('State stream error', error, st);
        },
        onDone: () {
          _log.warning('State stream closed — kp/kd auto-switching disabled');
        },
      ),
    );

    // 遥控器事件 → 通过仲裁器发送（ControlSource.yunzhuo）
    void onStreamError(Object error, StackTrace st, String name) {
      _log.severe('Controller $name stream error', error, st);
      if (!_disposed) {
        arbiter.fault('Controller $name stream error: $error');
      }
    }

    bool sendCommand(A action, String label) {
      if (!arbiter.command(action, ControlSource.yunzhuo)) {
        _log.warning(
          'YUNZHUO $label rejected — arbiter owner: ${arbiter.owner}',
        );
        return false;
      }
      return true;
    }

    void hardStopDog(String reason) {
      _l1StandingRequested = false;
      _latestControllerCommand = Vector3.zero();
      _cancelPendingStandUp(reason: reason);
      _lastWalkCommand = Vector3.zero();
      _walkCommandLimiter.reset();
      if (arbiter.state is Walking) {
        sendCommand(
          A.walk(Vector3.zero(), forceWheelStop: true),
          'walk(zero-hard-stop:$reason)',
        );
      }
    }

    if (controller case HardStopGamepad hardStopController) {
      _subscriptions.add(
        hardStopController.hardStop.listen(
          (_) => hardStopDog('input-watchdog'),
          onError: (Object e, StackTrace st) {
            hardStopDog('hard-stop-stream-error');
            onStreamError(e, st, 'hardStop');
          },
          onDone: () => hardStopDog('hard-stop-stream-closed'),
        ),
      );
    }

    Vector3 normalDogCommand(Vector3 direction) {
      final command = Vector3(
        _mapForward(direction.x),
        _mapLateral(direction.y),
        _mapYaw(direction.z),
      );
      _latestControllerCommand = Vector3.copy(command);
      if (command.x != 0 || command.y != 0 || command.z != 0) {
        _l1StandingRequested = false;
        _cancelPendingStandUp(
          reason: 'controller command resumed before the robot settled',
        );
      }
      return command;
    }

    void sendWalkVector(
      Vector3 target,
      String label, {
      DateTime? receivedAt,
      bool applyRateLimit = true,
    }) {
      final command = applyRateLimit
          ? _walkCommandLimiter.limit(target, receivedAt ?? commandClock())
          : target;
      _lastWalkCommand = Vector3.copy(command);
      if (command.x == 0 && command.y == 0 && command.z == 0) {
        if (arbiter.state is Walking) {
          sendCommand(A.walk(Vector3.zero()), label);
        }
        return;
      }
      _log.info(
        'WALK fwd=${command.x.toStringAsFixed(2)} '
        'lat=${command.y.toStringAsFixed(2)} '
        'yaw=${command.z.toStringAsFixed(2)}',
      );
      sendCommand(A.walk(command), label);
    }

    _subscriptions.add(
      controller.direction.listen(
        (direction) {
          if (!_operatorEnabled) return;
          if (controller case HardStopGamepad c when c.hardStopActive) {
            hardStopDog('input-watchdog'); // 超时补零不能解除异常停车。
            return;
          }
          if (_profileSwitchInProgress) {
            return; // Ignore, never queue joystick input.
          }
          // Operator-requested direct input; retain bounds and hard-stop checks.
          sendWalkVector(
            normalDogCommand(direction),
            'walk',
            applyRateLimit: false,
          );
        },
        onError: (Object e, StackTrace st) {
          hardStopDog('direction-stream-error');
          onStreamError(e, st, 'direction');
        },
        onDone: () {
          hardStopDog('direction-stream-closed');
          _log.warning('Controller direction stream closed');
        },
      ),
    );
    _subscriptions.add(
      controller.standup.listen(
        (_) {
          if (_profileSwitchInProgress) return;
          if (!_standUpEnabled) {
            _log.info('L1 ignored: motor enable has not completed');
            return;
          }
          if (arbiter.state is Walking) {
            _requestStandUpAfterSettle(button: 'L1', label: 'standUp');
            return;
          }
          _log.info('L1 → standUp');
          _l1StandingRequested = sendCommand(const A.standUp(), 'standUp');
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'standup'),
        onDone: () => _log.warning('Controller standup stream closed'),
      ),
    );
    _subscriptions.add(
      controller.sitdown.listen(
        (_) {
          _l1StandingRequested = false;
          _cancelPendingStandUp(reason: 'L2 requested');
          _log.info('L2 → sitDown');
          sendCommand(const A.sitDown(), 'sitDown');
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'sitdown'),
        onDone: () => _log.warning('Controller sitdown stream closed'),
      ),
    );
    _subscriptions.add(
      controller.enabled.listen(
        (enabled) async {
          _log.info('H enable=$enabled');
          _l1StandingRequested = false;
          final generation = ++_standUpEnableGeneration;
          _setStandUpEnabled(false);
          _operatorEnabled = enabled;
          if (enabled) {
            _walkCommandLimiter.reset();
            _motorEnablePending++;
            try {
              final requestEnable = requestMotorEnable;
              if (requestEnable != null) {
                await requestEnable();
              } else {
                await joint.enable();
              }
              // Ignore completions from an earlier H/red-button session.
              if (_disposed || generation != _standUpEnableGeneration) return;
              if (_operatorEnabled) {
                _setStandUpEnabled(true);
                onMotorEnableChanged?.call(true);
              }
            } catch (e, st) {
              if (_disposed || generation != _standUpEnableGeneration) return;
              _setStandUpEnabled(false);
              _operatorEnabled = false;
              hardStopDog('enable-failed');
              onMotorEnableChanged?.call(false);
              _log.severe('Motor enable refused: $e', e, st);
            } finally {
              _motorEnablePending--;
            }
          } else {
            hardStopDog('motors-disabled');
            onMotorEnableChanged?.call(false);
            joint.disable();
          }
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'enabled'),
        onDone: () => _log.warning('Controller enabled stream closed'),
      ),
    );
    _subscriptions.add(
      controller.red.listen(
        (_) {
          _log.info('红键 → disable motors + clear errors');
          ++_standUpEnableGeneration;
          _setStandUpEnabled(false);
          _operatorEnabled = false;
          hardStopDog('red-button');
          onMotorEnableChanged?.call(false);
          joint.disable(clearErrors: true);
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'red'),
        onDone: () => _log.warning('Controller red stream closed'),
      ),
    );
    _subscriptions.add(
      controller.idle.listen(
        (_) {
          if (_profileSwitchInProgress) return;
          _l1StandingRequested = false;
          if (arbiter.state is Walking) {
            _requestStandUpAfterSettle(button: 'R1', label: 'standUp(R1)');
            return;
          }
          _log.info('R1 → standUp');
          sendCommand(const A.standUp(), 'standUp(R1)');
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'idle(R1)'),
        onDone: () => _log.warning('Controller idle(R1) stream closed'),
      ),
    );
    _subscriptions.add(
      controller.calibrate.listen(
        (_) {
          if (arbiter.state is! Grounded) return;
          _log.info('标零组合键 → setZero+save');
          joint
            ..setZeroPosition()
            ..setZeroSigned()
            ..saveParameters();
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'calibrate'),
        onDone: () => _log.warning('Controller calibrate stream closed'),
      ),
    );
    _subscriptions.add(
      controller.switchProfile.listen(
        (_) async {
          try {
            await requestProfileSwitch();
          } catch (e, st) {
            // Failed model loading keeps the old model and fixed standing hold.
            _log.warning(
              'R2 profile switch failed; previous mode retained',
              e,
              st,
            );
          }
        },
        onError: (Object e, StackTrace st) =>
            onStreamError(e, st, 'switchProfile'),
        onDone: () => _log.warning('Controller switchProfile stream closed'),
      ),
    );
  }

  /// Radio R2 and authenticated web selection share the same commit guards.
  Future<void> requestProfileSwitch() async {
    if (_profileSwitchInProgress || !canSwitchProfile) {
      throw StateError(
        'R2 requires grounded or completed L1 standing with centered sticks (${arbiter.state})',
      );
    }
    final switchProfile = onProfileSwitch;
    if (switchProfile == null) throw StateError('Profile manager not ready');
    _profileSwitchInProgress = true;
    _profileSwitchState = arbiter.state;
    _profileSwitchEnableGeneration = _standUpEnableGeneration;
    arbiter.profileSwitchInProgress = true;
    final switchTimer = Stopwatch()..start();
    _log.info('R2 → switchProfile');
    try {
      await switchProfile();
      _log.info(
        'R2 profile switch complete in ${switchTimer.elapsedMicroseconds}us; standing target retained',
      );
    } finally {
      arbiter.profileSwitchInProgress = false;
      _profileSwitchInProgress = false;
      _profileSwitchState = null;
      _profileSwitchEnableGeneration = null;
    }
  }

  void _setStandUpEnabled(bool enabled) {
    _standUpEnabled = enabled;
    if (controller case RealController realController) {
      realController.setStandUpEnabled(enabled);
    }
  }

  /// 切换策略时更新全部增益参数。
  ///
  /// 只在机器人处于 Grounded 状态（由调用方保证）时调用。
  /// 下一帧 arbiter.stateStream 事件到来时新增益自动生效。
  void switchGains({
    required JointsMatrix inferKp,
    required JointsMatrix inferKd,
    required JointsMatrix standUpKp,
    required JointsMatrix standUpKd,
    required JointsMatrix sitDownKp,
    required JointsMatrix sitDownKd,
  }) {
    this.inferKp = inferKp;
    this.inferKd = inferKd;
    this.standUpKp = standUpKp;
    this.standUpKd = standUpKd;
    this.sitDownKp = sitDownKp;
    this.sitDownKd = sitDownKd;
  }

  /// Applies profile-specific command bounds without recreating controller
  /// subscriptions during a policy switch.
  void switchCommandProfile({
    required double commandVxMax,
    required double commandVyMax,
    required double commandYawMax,
    required double forwardMinCommand,
    required double lateralMinCommand,
    required double yawMinCommand,
  }) {
    this.commandVxMax = commandVxMax;
    this.commandVyMax = commandVyMax;
    this.commandYawMax = commandYawMax;
    this.forwardMinCommand = forwardMinCommand;
    this.lateralMinCommand = lateralMinCommand;
    this.yawMinCommand = yawMinCommand;
  }

  bool get _controllerCommandIsZero =>
      _latestControllerCommand.x == 0 &&
      _latestControllerCommand.y == 0 &&
      _latestControllerCommand.z == 0;

  double get _maxWheelSpeed {
    final velocity = joint.velocity;
    var maximum = 0.0;
    for (final value in <double>[
      velocity.frFoot,
      velocity.flFoot,
      velocity.rrFoot,
      velocity.rlFoot,
    ]) {
      if (!value.isFinite) return double.nan;
      if (value.abs() > maximum) maximum = value.abs();
    }
    return maximum;
  }

  double get _maxGyro {
    final gyro = imu.gyroscope;
    var maximum = 0.0;
    for (final value in <double>[gyro.x, gyro.y, gyro.z]) {
      if (!value.isFinite) return double.nan;
      if (value.abs() > maximum) maximum = value.abs();
    }
    return maximum;
  }

  void _requestStandUpAfterSettle({
    required String button,
    required String label,
  }) {
    if (!_controllerCommandIsZero) {
      _log.warning(
        '$button ignored while the controller command is non-zero — release the stick first',
      );
      return;
    }
    if (_standUpSettleTimer != null) {
      _log.info('$button standUp already waiting for the robot to settle');
      return;
    }

    var stableFor = Duration.zero;
    var waitedFor = Duration.zero;
    _log.info(
      '$button → wait for zero-command settle before fixed standUp '
      '(wheel<$_standUpWheelSpeedMax rad/s, gyro<$_standUpGyroMax rad/s)',
    );
    _standUpSettleTimer = Timer.periodic(_standUpSettlePoll, (timer) {
      if (_disposed || arbiter.state is! Walking) {
        _cancelPendingStandUp();
        return;
      }
      if (!_controllerCommandIsZero) {
        _cancelPendingStandUp(
          reason: 'controller command resumed before the robot settled',
        );
        return;
      }

      // A centered stick can still leave a non-zero deceleration command.
      if (_lastWalkCommand.length2 != 0) {
        stableFor = Duration.zero;
        return;
      }
      waitedFor += _standUpSettlePoll;
      final wheelSpeed = _maxWheelSpeed;
      final gyro = _maxGyro;
      final settled =
          wheelSpeed.isFinite &&
          gyro.isFinite &&
          wheelSpeed < _standUpWheelSpeedMax &&
          gyro < _standUpGyroMax;
      stableFor = settled ? stableFor + _standUpSettlePoll : Duration.zero;

      if (stableFor >= _standUpSettleDuration) {
        _cancelPendingStandUp();
        _log.info(
          '$button settled → standUp '
          '(wheel=${wheelSpeed.toStringAsFixed(2)}, gyro=${gyro.toStringAsFixed(3)})',
        );
        if (!arbiter.command(const A.standUp(), ControlSource.yunzhuo)) {
          _log.warning(
            'YUNZHUO $label rejected — arbiter owner: ${arbiter.owner}',
          );
        } else {
          _l1StandingRequested = button == 'L1';
        }
        return;
      }

      if (waitedFor >= _standUpSettleTimeout) {
        _cancelPendingStandUp();
        _log.warning(
          '$button standUp settle timeout — keep ONNX zero-command balance '
          '(wheel=${wheelSpeed.toStringAsFixed(2)}, gyro=${gyro.toStringAsFixed(3)})',
        );
      }
    });
  }

  void _cancelPendingStandUp({String? reason}) {
    final timer = _standUpSettleTimer;
    if (timer == null) return;
    timer.cancel();
    _standUpSettleTimer = null;
    if (reason != null) {
      _log.info('Pending standUp cancelled — $reason');
    }
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_standUpEnableGeneration;
    _setStandUpEnabled(false);
    _cancelPendingStandUp();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
