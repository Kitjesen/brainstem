import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

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
    if (!blocksControllerCommands) {
      throw StateError('Body-height handover is not active');
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
    final progress = (_frameIndex / intervalCount).clamp(0.0, 1.0).toDouble();
    final alpha = progress * progress * (3.0 - 2.0 * progress);
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
