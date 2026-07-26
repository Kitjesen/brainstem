import 'package:han_dog/src/body_height_handover.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

typedef MotorActionGate =
    JointsMatrix Function(JointsMatrix desired, JointsMatrix measured);
typedef MotorActionSender = bool Function(JointsMatrix desired);
typedef MotorGainWriter = void Function(JointsMatrix kp, JointsMatrix kd);

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
      return sendAction(measuredPosition.discardFoot());
    }

    var desired = policyAction;
    final activeHandover = handover;
    final appliesHandover = activeHandover != null && activeHandover.isRunning;
    if (appliesHandover) {
      final frame = activeHandover.preview(policyAction);
      desired = frame.action;
      setGains(frame.kp, frame.kd);
    }

    final gated = gateAction(desired, measuredPosition);
    if (!sendAction(gated)) return false;
    if (appliesHandover) {
      activeHandover.markApplied();
    }
    return true;
  }
}
