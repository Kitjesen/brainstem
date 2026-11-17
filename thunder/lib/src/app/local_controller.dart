import '../gamepad.dart';
import '../real_controller.dart';

typedef LocalControllerCandidate = ({Gamepad controller, bool Function() open});

/// Only the serial receiver is observed; other controller families stay active.
bool isReceiverObservation(Gamepad? controller, {required bool observeOnly}) =>
    observeOnly && controller is RealController;

bool canAttachLocalController({
  required bool grounded,
  required bool motorOutputEnabled,
  required bool motorEnablePending,
  required bool calibrationPending,
  required bool recoverySelected,
  required bool healthy,
}) =>
    grounded &&
    !motorOutputEnabled &&
    !motorEnablePending &&
    !calibrationPending &&
    !recoverySelected &&
    healthy;

/// Keep an attached input; otherwise open the first available candidate.
Gamepad? openLocalController({
  required Gamepad? current,
  required Iterable<LocalControllerCandidate Function()> candidates,
}) {
  if (current != null) return current;
  for (final create in candidates) {
    final candidate = create();
    var opened = false;
    try {
      opened = candidate.open();
      if (opened) return candidate.controller;
    } finally {
      if (!opened) candidate.controller.dispose();
    }
  }
  return null;
}
