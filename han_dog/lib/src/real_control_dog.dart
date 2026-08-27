// YUNZHUO 遥控器驱动桥接：将摇杆信号转换为 FSM 动作（Walk/StandUp/SitDown/Idle）。

import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

final _log = Logger('han_dog.control');

class RealControlDog {
  final Brain brain;
  final ControlArbiter arbiter;
  final RealImu imu;
  final RealJoint joint;
  final Gamepad controller;
  final RobotProfile? initialProfile;
  final BodyHeightHandover? bodyHeightHandover;
  JointsMatrix inferKp;
  JointsMatrix inferKd;
  JointsMatrix standUpKp;
  JointsMatrix standUpKd;
  JointsMatrix sitDownKp;
  JointsMatrix sitDownKd;
  (double, double, double) velocityCommandMin;
  (double, double, double) velocityCommandMax;

  /// 策略切换回调（由外部 ProfileManager 设置）。
  void Function()? onProfileSwitch;

  /// 电机使能状态变化回调（由外部设置，用于同步 motorOutputEnabled 标志）。
  void Function(bool enabled)? onMotorEnableChanged;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _bodyHeightTimer;
  double _bodyHeightAxis = 0;
  double? _bodyHeightCommand;
  bool _motorOutputEnabled;

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
    required this.controller,
    this.initialProfile,
    this.bodyHeightHandover,
    bool motorOutputInitiallyEnabled = false,
    this.velocityCommandMin = (-3.0, -3.0, -3.0),
    this.velocityCommandMax = (3.0, 3.0, 3.0),
  }) : _motorOutputEnabled = motorOutputInitiallyEnabled {
    _validateVelocityBounds(velocityCommandMin, velocityCommandMax);
    _configureBodyHeightControl();

    // 监听 CMS 状态变化，自动设置对应的 kp/kd
    _subscriptions.add(
      arbiter.stateStream.listen(
        (state) {
          final handover = bodyHeightHandover;
          switch (state) {
            case Walking():
              if (handover?.isRequested == true) {
                handover!.begin();
              }
              if (handover?.blocksControllerCommands != true) {
                joint.kpExt = inferKp;
                joint.kdExt = inferKd;
              }
            case Transitioning(:final target):
              _cancelBodyHeightHandover();
              if (target is StandUpCommand) {
                joint.kpExt = standUpKp;
                joint.kdExt = standUpKd;
              } else {
                joint.kpExt = sitDownKp;
                joint.kdExt = sitDownKd;
              }
            case Standing():
              if (handover?.blocksControllerCommands == true &&
                  handover?.isRequested != true) {
                _cancelBodyHeightHandover();
              }
            case Grounded() || Zero():
              _cancelBodyHeightHandover();
          }
        },
        onError: (Object error, StackTrace st) {
          _cancelBodyHeightHandover();
          _log.severe('State stream error', error, st);
        },
        onDone: () {
          _log.warning('State stream closed — kp/kd auto-switching disabled');
        },
      ),
    );

    // 遥控器事件 → 通过仲裁器发送（ControlSource.yunzhuo）
    void onStreamError(Object error, StackTrace st, String name) {
      _cancelBodyHeightHandover();
      _log.severe('Controller $name stream error', error, st);
      if (!_disposed) {
        arbiter.fault('Controller $name stream error: $error');
      }
    }

    bool sendCommand(A action, String label) {
      final accepted = arbiter.command(action, ControlSource.yunzhuo);
      if (!accepted) {
        _log.warning(
          'YUNZHUO $label rejected — arbiter owner: ${arbiter.owner}',
        );
      }
      return accepted;
    }

    _subscriptions.add(
      controller.direction.listen(
        (direction) {
          // 摇杆死区：中位附近的微小值归零（SBUS ±1/720 ≈ 0.0014）
          const deadzone = 0.02;
          if (!direction.x.isFinite ||
              !direction.y.isFinite ||
              !direction.z.isFinite) {
            _log.warning('Non-finite controller direction ignored');
            return;
          }

          final rawVx = direction.x.abs() < deadzone ? 0.0 : direction.x;
          final rawVy = direction.y.abs() < deadzone ? 0.0 : direction.y;
          final rawYaw = direction.z.abs() < deadzone ? 0.0 : direction.z;
          final vx = rawVx
              .clamp(velocityCommandMin.$1, velocityCommandMax.$1)
              .toDouble();
          final vy = rawVy
              .clamp(velocityCommandMin.$2, velocityCommandMax.$2)
              .toDouble();
          final yaw = rawYaw
              .clamp(velocityCommandMin.$3, velocityCommandMax.$3)
              .toDouble();

          final handover = bodyHeightHandover;
          if (handover?.blocksControllerCommands == true) {
            return;
          }

          if (vx == 0 && vy == 0 && yaw == 0) {
            // 摇杆归零：发 walk(0,0,0) 让策略减速，保持 Walking 状态。
            if (arbiter.state is Walking) {
              sendCommand(A.walk(Vector3.zero()), 'walk(zero)');
            }
            return;
          }
          if (handover != null && arbiter.state is Standing) {
            _requestBodyHeightHandover();
            return;
          }
          // Keep every physical-controller command inside the policy envelope.
          final cmd = Vector3(vx, vy, yaw);
          _log.info(
            'WALK fwd=${vx.toStringAsFixed(2)} '
            'lat=${vy.toStringAsFixed(2)} '
            'yaw=${yaw.toStringAsFixed(2)}',
          );
          sendCommand(A.walk(cmd), 'walk');
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'direction'),
        onDone: () => _log.warning('Controller direction stream closed'),
      ),
    );
    _subscriptions.add(
      controller.standup.listen(
        (_) {
          _cancelBodyHeightHandover();
          _log.info('L1 → standUp');
          sendCommand(const A.standUp(), 'standUp');
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'standup'),
        onDone: () => _log.warning('Controller standup stream closed'),
      ),
    );
    _subscriptions.add(
      controller.sitdown.listen(
        (_) {
          _cancelBodyHeightHandover();
          _log.info('L2 → sitDown');
          sendCommand(const A.sitDown(), 'sitDown');
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'sitdown'),
        onDone: () => _log.warning('Controller sitdown stream closed'),
      ),
    );
    _subscriptions.add(
      controller.enabled.listen(
        (enabled) {
          _log.info('H enable=$enabled');
          if (enabled) {
            joint.enable();
            _motorOutputEnabled = true;
            final handover = bodyHeightHandover;
            if (handover?.blocksControllerCommands == true) {
              if (arbiter.state is Walking) {
                handover!.restartFrom(joint.position);
              } else {
                _cancelBodyHeightHandover();
              }
            }
          } else {
            _motorOutputEnabled = false;
            _bodyHeightAxis = 0;
            bodyHeightHandover?.suspend();
            joint.disable();
          }
          onMotorEnableChanged?.call(enabled);
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'enabled'),
        onDone: () => _log.warning('Controller enabled stream closed'),
      ),
    );
    _subscriptions.add(
      controller.red.listen(
        (_) {
          _log.info('红键 → disable motors + clear errors');
          _motorOutputEnabled = false;
          _bodyHeightAxis = 0;
          bodyHeightHandover?.suspend();
          joint.disable(clearErrors: true);
          onMotorEnableChanged?.call(false);
        },
        onError: (Object e, StackTrace st) => onStreamError(e, st, 'red'),
        onDone: () => _log.warning('Controller red stream closed'),
      ),
    );
    _subscriptions.add(
      controller.idle.listen(
        (_) {
          final canceledPendingWalk = bodyHeightHandover?.isRequested == true;
          _cancelBodyHeightHandover();
          final profile = initialProfile;
          if (profile != null &&
              isBodyHeightObservationType(profile.observationType) &&
              arbiter.state is Standing) {
            _log.info('R1 → reset body height');
            final accepted = sendCommand(
              A.setBodyHeight(profile.bodyHeightCommand),
              'reset body height(R1)',
            );
            if (accepted) {
              _bodyHeightAxis = 0;
              _bodyHeightCommand = profile.bodyHeightCommand;
            } else {
              _log.warning('R1 body-height reset rejected; input preserved');
            }
            if (canceledPendingWalk) {
              sendCommand(
                const A.standUp(),
                'standUp after cancelled body-height request(R1)',
              );
            }
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
        (_) {
          if (initialProfile != null &&
              isBodyHeightObservationType(initialProfile!.observationType)) {
            _log.warning(
              'R2 profile switch ignored in body-height remote mode',
            );
            return;
          }
          if (arbiter.state is! Grounded && arbiter.state is! Standing) {
            _log.warning(
              'R2 profile switch rejected: must be grounded or standing (${arbiter.state})',
            );
            return;
          }
          _log.info('R2 → switchProfile');
          try {
            onProfileSwitch?.call();
          } catch (e, st) {
            _log.severe('onProfileSwitch callback error', e, st);
            arbiter.fault('Profile switch error: $e');
          }
        },
        onError: (Object e, StackTrace st) =>
            onStreamError(e, st, 'switchProfile'),
        onDone: () => _log.warning('Controller switchProfile stream closed'),
      ),
    );
  }

  void _configureBodyHeightControl() {
    final profile = initialProfile;
    if (profile == null ||
        !isBodyHeightObservationType(profile.observationType)) {
      return;
    }
    if (bodyHeightHandover == null) {
      throw ArgumentError.notNull('bodyHeightHandover');
    }

    final defaultHeight = profile.bodyHeightCommand;
    final minHeight = profile.minBodyHeightCommand;
    final maxHeight = profile.maxBodyHeightCommand;
    final rateMetersPerSecond = profile.bodyHeightRateLimit;
    if (!defaultHeight.isFinite ||
        !minHeight.isFinite ||
        !maxHeight.isFinite ||
        minHeight > maxHeight ||
        defaultHeight < minHeight ||
        defaultHeight > maxHeight) {
      throw ArgumentError(
        'Body-height profile bounds must be finite, ordered, and contain '
        'the default command',
      );
    }
    if (controller is! BodyHeightAxisInput) {
      throw ArgumentError.value(
        controller,
        'controller',
        'must implement BodyHeightAxisInput for a body-height profile',
      );
    }
    final bodyHeightController = controller as BodyHeightAxisInput;

    _bodyHeightCommand = defaultHeight;
    _subscriptions.add(
      bodyHeightController.bodyHeightAxis.listen(
        (axis) {
          final handover = bodyHeightHandover!;
          if (handover.blocksControllerCommands) {
            _bodyHeightAxis = 0;
            return;
          }
          if (!axis.isFinite) {
            _bodyHeightAxis = 0;
            _log.warning('Non-finite body-height axis ignored');
            return;
          }
          final normalized = axis.abs() < 0.10 ? 0.0 : axis.clamp(-1.0, 1.0);
          final state = arbiter.state;
          if (state is! Walking && state is! Standing) {
            _bodyHeightAxis = 0;
            return;
          }
          if (normalized != 0 && state is Standing) {
            _bodyHeightAxis = 0;
            _requestBodyHeightHandover();
            return;
          }
          if (_bodyHeightAxis == 0 && normalized != 0) {
            final appliedHeight = brain.bodyHeightCommand;
            if (appliedHeight.isFinite) {
              _bodyHeightCommand = appliedHeight
                  .clamp(minHeight, maxHeight)
                  .toDouble();
            } else {
              _log.warning(
                'Non-finite applied body height ignored during handover',
              );
            }
          }
          _bodyHeightAxis = normalized.toDouble();
        },
        onError: (Object error, StackTrace st) {
          _cancelBodyHeightHandover();
          _log.severe('Controller bodyHeightAxis stream error', error, st);
          if (!_disposed) {
            arbiter.fault('Controller bodyHeightAxis stream error: $error');
          }
        },
        onDone: () => _log.warning('Controller bodyHeightAxis stream closed'),
      ),
    );
    _bodyHeightTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (bodyHeightHandover!.blocksControllerCommands) {
        _bodyHeightAxis = 0;
        return;
      }
      if (_bodyHeightAxis == 0 || _disposed || arbiter.state is! Walking) {
        return;
      }
      const tickSeconds = 0.020;
      final next =
          (_bodyHeightCommand! +
                  _bodyHeightAxis * rateMetersPerSecond * tickSeconds)
              .clamp(minHeight, maxHeight)
              .toDouble();
      if (arbiter.command(A.setBodyHeight(next), ControlSource.yunzhuo)) {
        _bodyHeightCommand = next;
      }
    });
  }

  bool _requestBodyHeightHandover() {
    final profile = initialProfile;
    final handover = bodyHeightHandover;
    if (profile == null ||
        !isBodyHeightObservationType(profile.observationType) ||
        handover == null) {
      return false;
    }
    if (!_motorOutputEnabled) {
      _bodyHeightAxis = 0;
      _log.fine('Body-height handover ignored while motor output is disabled');
      return false;
    }
    if (handover.blocksControllerCommands) return false;

    final defaultHeight = profile.bodyHeightCommand;
    final heightAccepted = arbiter.command(
      A.setBodyHeight(defaultHeight),
      ControlSource.yunzhuo,
    );
    if (!heightAccepted) {
      _log.warning(
        'YUNZHUO reset body height before handover rejected — '
        'arbiter owner: ${arbiter.owner}',
      );
      handover.cancel();
      return false;
    }

    _bodyHeightCommand = defaultHeight;
    _bodyHeightAxis = 0;
    handover.requestFrom(joint.position);
    final walkAccepted = arbiter.command(
      A.walk(Vector3.zero()),
      ControlSource.yunzhuo,
    );
    if (!walkAccepted) {
      _log.warning(
        'YUNZHUO walk(zero) before handover rejected — '
        'arbiter owner: ${arbiter.owner}',
      );
      handover.cancel();
      return false;
    }
    return true;
  }

  void _cancelBodyHeightHandover() {
    _bodyHeightAxis = 0;
    bodyHeightHandover?.cancel();
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

  /// Update the active policy's per-axis velocity envelope.
  void switchVelocityBounds({
    required (double, double, double) velocityCommandMin,
    required (double, double, double) velocityCommandMax,
  }) {
    _validateVelocityBounds(velocityCommandMin, velocityCommandMax);
    this.velocityCommandMin = velocityCommandMin;
    this.velocityCommandMax = velocityCommandMax;
  }

  static void _validateVelocityBounds(
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

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelBodyHeightHandover();
    _bodyHeightTimer?.cancel();
    _bodyHeightTimer = null;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
