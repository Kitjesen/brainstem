import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

void main() {
  Grounded groundedState() {
    final subscription = Stream<History>.empty().listen((_) {});
    addTearDown(subscription.cancel);
    return Grounded(subscription);
  }

  String? check({
    required S state,
    JointsMatrix? position,
    JointsMatrix? velocity,
    bool hasFreshJointTelemetry = true,
    bool hasUnrecoveredMotorFaults = false,
  }) => MotorEnableSafety.blockReason(
    state: state,
    position: position ?? JointsMatrix.zero(),
    velocity: velocity ?? JointsMatrix.zero(),
    jointLimitRad: 3.14,
    hasFreshJointTelemetry: hasFreshJointTelemetry,
    hasUnrecoveredMotorFaults: hasUnrecoveredMotorFaults,
  );

  group('MotorEnableSafety', () {
    test('allows a settled grounded pose with fresh telemetry', () {
      expect(check(state: groundedState()), isNull);
    });

    test(
      'checks leg telemetry in raw CAN order without counting foot motors',
      () {
        final frequencies = List<double>.filled(16, 50);
        frequencies[3] = 0; // FR foot: intentionally not part of the leg gate.
        expect(MotorEnableSafety.hasFreshLegCanTelemetry(frequencies), isTrue);

        frequencies[14] = 0; // RL calf: must block Enable.
        expect(MotorEnableSafety.hasFreshLegCanTelemetry(frequencies), isFalse);
      },
    );

    test('rejects enabling while CMS is not grounded', () {
      expect(check(state: const Zero()), contains('CMS must be Grounded'));
    });

    test('rejects a leg joint outside its safe angle limit', () {
      final positions = List<double>.filled(16, 0);
      positions[11] = 3.2;

      expect(
        check(
          state: groundedState(),
          position: JointsMatrix.fromList(positions),
        ),
        contains('leg joint 11'),
      );
    });

    test('does not apply the angle limit to continuous foot wheels', () {
      final positions = List<double>.filled(16, 0);
      positions[12] = 99;

      expect(
        check(
          state: groundedState(),
          position: JointsMatrix.fromList(positions),
        ),
        isNull,
      );
    });

    test('rejects moving legs and stale joint telemetry', () {
      final velocity = List<double>.filled(16, 0);
      velocity[0] = 0.6;

      expect(
        check(
          state: groundedState(),
          velocity: JointsMatrix.fromList(velocity),
        ),
        contains('moving too fast'),
      );
      expect(
        check(state: groundedState(), hasFreshJointTelemetry: false),
        contains('not fresh enough'),
      );
    });

    test('rejects Enable while motor fault recovery is pending', () {
      expect(
        check(state: groundedState(), hasUnrecoveredMotorFaults: true),
        'motor fault recovery is pending',
      );
    });

    test('rejects a pose outside the grounded reference window', () {
      final position = List<double>.filled(16, 0.0);
      position[4] = 0.6;

      expect(
        MotorEnableSafety.blockReason(
          state: groundedState(),
          position: JointsMatrix.fromList(position),
          velocity: JointsMatrix.zero(),
          jointLimitRad: 3.14,
          hasFreshJointTelemetry: true,
          safePose: JointsMatrix.zero(),
          maxSafePoseErrorRad: 0.5,
        ),
        contains('safe grounded pose'),
      );
    });
  });
}
