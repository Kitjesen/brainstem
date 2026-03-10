// YUNZHUO 遥控器驱动桥接：将摇杆信号转换为 FSM 动作（Walk/StandUp/SitDown/Idle）。

import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

final _log = Logger('han_dog.control');

/// 摇杆归零后触发 Idle 命令的等待时长。
const _idleTimeout = Duration(seconds: 5);

class RealControlDog {
  final Brain brain;
  final ControlArbiter arbiter;
  final RealImu imu;
  final RealJoint joint;
  final RealController controller;
  JointsMatrix inferKp;
  JointsMatrix inferKd;
  JointsMatrix standUpKp;
  JointsMatrix standUpKd;
  JointsMatrix sitDownKp;
  JointsMatrix sitDownKd;

  /// 策略切换回调（由外部 ProfileManager 设置）。
  void Function()? onProfileSwitch;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _idleTimer;

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
  }) {
    // 监听 CMS 状态变化，自动设置对应的 kp/kd
    _subscriptions.add(arbiter.stateStream.listen(
      (state) {
        switch (state) {
          case Walking():
            joint.kpExt = inferKp;
            joint.kdExt = inferKd;
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
    ));

    // 遥控器事件 → 通过仲裁器发送（ControlSource.yunzhuo）
    void onStreamError(Object error, StackTrace st, String name) {
      _log.severe('Controller $name stream error', error, st);
      arbiter.fault('Controller $name stream error: $error');
    }

    void sendCommand(A action, String label) {
      if (!arbiter.command(action, ControlSource.yunzhuo)) {
        _log.warning('YUNZHUO $label rejected — arbiter owner: ${arbiter.owner}');
      }
    }

    _subscriptions.add(controller.direction.listen(
      (direction) {
        if (direction.x == 0 && direction.y == 0 && direction.z == 0) {
          _idleTimer ??= Timer(_idleTimeout, () {
            _idleTimer = null;
            sendCommand(const A.idle(), 'idle(timeout)');
          });
          return;
        }
        _idleTimer?.cancel();
        _idleTimer = null;
        sendCommand(
          A.walk(Vector3(direction.x, direction.y, direction.z)),
          'walk',
        );
      },
      onError: (Object e, StackTrace st) => onStreamError(e, st, 'direction'),
      onDone: () => _log.warning('Controller direction stream closed'),
    ));
    _subscriptions.add(controller.standup.listen(
      (_) {
        _idleTimer?.cancel();
        _idleTimer = null;
        _log.info('L1 → standUp');
        sendCommand(const A.standUp(), 'standUp');
      },
      onError: (Object e, StackTrace st) => onStreamError(e, st, 'standup'),
      onDone: () => _log.warning('Controller standup stream closed'),
    ));
    _subscriptions.add(controller.sitdown.listen(
      (_) {
        _idleTimer?.cancel();
        _idleTimer = null;
        _log.info('L2 → sitDown');
        sendCommand(const A.sitDown(), 'sitDown');
      },
      onError: (Object e, StackTrace st) => onStreamError(e, st, 'sitdown'),
      onDone: () => _log.warning('Controller sitdown stream closed'),
    ));
    _subscriptions.add(controller.enabled.listen(
      (enabled) {
        _log.info('H enable=$enabled');
        if (enabled) {
          joint.enable();
        } else {
          joint.disable();
        }
      },
      onError: (Object e, StackTrace st) => onStreamError(e, st, 'enabled'),
      onDone: () => _log.warning('Controller enabled stream closed'),
    ));
    _subscriptions.add(controller.red.listen(
      (_) {
        _idleTimer?.cancel();
        _idleTimer = null;
        _log.info('红键 → disable motors');
        joint.disable();
      },
      onError: (Object e, StackTrace st) => onStreamError(e, st, 'red'),
      onDone: () => _log.warning('Controller red stream closed'),
    ));
    _subscriptions.add(controller.idle.listen(
      (_) {
        _idleTimer?.cancel();
        _idleTimer = null;
        _log.info('R1 → standUp');
        sendCommand(const A.standUp(), 'standUp(R1)');
      },
      onError: (Object e, StackTrace st) => onStreamError(e, st, 'idle(R1)'),
      onDone: () => _log.warning('Controller idle(R1) stream closed'),
    ));
    _subscriptions.add(controller.calibrate.listen(
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
    ));
    _subscriptions.add(controller.switchProfile.listen(
      (_) {
        if (arbiter.state is! Grounded) {
          _log.warning('R2 profile switch rejected: not grounded (${arbiter.state})');
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
    ));
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

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
