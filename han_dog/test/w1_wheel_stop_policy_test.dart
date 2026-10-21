import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockImu extends Mock implements ImuService {}

class MockJoint extends Mock implements JointService {}

void main() {
  final profilePath = Platform.environment['W1_TEST_PROFILE'];
  final modelPath = Platform.environment['W1_TEST_MODEL'];
  final hasFixture = profilePath != null && modelPath != null;

  test('W1 opts out; absent field preserves old profiles', () {
    final json =
        jsonDecode(File(profilePath!).readAsStringSync())
            as Map<String, dynamic>;
    expect(RobotProfile.fromJson(json).forceZeroWheelOnStop, isFalse);
    json.remove('forceZeroWheelOnStop');
    expect(RobotProfile.fromJson(json).forceZeroWheelOnStop, isTrue);
  }, skip: !hasFixture);

  test(
    'real W1 inference: normal stop, hard stop, raw history, entry and profile switch',
    () async {
      final profile = RobotProfile.fromJson(
        jsonDecode(File(profilePath!).readAsStringSync()) as Map<String, dynamic>,
      );
      final imu = MockImu();
      final joint = MockJoint();
      when(() => imu.gyroscope).thenReturn(Vector3.zero());
      when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
      when(() => imu.initialGyroscope).thenReturn(Vector3.zero());
      when(() => imu.initialProjectedGravity).thenReturn(Vector3(0, 0, -1));
      when(() => joint.position).thenReturn(profile.standingPose);
      when(() => joint.initialPosition).thenReturn(profile.standingPose);
      when(() => joint.velocity).thenReturn(JointsMatrix.zero());
      when(() => joint.initialVelocity).thenReturn(JointsMatrix.zero());

      final aClock = StreamController<void>.broadcast();
      final bClock = StreamController<void>.broadcast();
      Brain create(StreamController<void> clock, bool forceZero) => Brain(
        imu: imu,
        joint: joint,
        clock: clock,
        standingPose: profile.standingPose,
        sittingPose: profile.sittingPose,
        observationBuilder: profile.toObservationBuilder(),
        forceZeroWheelOnStop: forceZero,
      );
      final a = create(aClock, profile.forceZeroWheelOnStop);
      final b = create(bClock, true);
      StreamSubscription<History>? aSub;
      StreamSubscription<History>? bSub;
      try {
        await a.loadModel(modelPath!);
        await b.loadModel(modelPath);
        aSub = a.walk.doing(Vector3.zero()).listen(a.memory.add);
        bSub = b.walk.doing(Vector3.zero()).listen(b.memory.add);
        var policyWheelsNonZero = false;
        for (var i = 0; i < 65; i++) {
          a.walk.forceWheelStop = i >= 32 && i < 45;
          b.walk.forceWheelStop = a.walk.forceWheelStop;
          // Exercise nonzero commands too: the legacy profile must not mask them.
          final direction = Vector3(i >= 55 ? 0.4 : 0, 0, 0);
          a.walk.direction = direction;
          b.walk.direction = direction;
          final ah = await a.tick();
          final bh = await b.tick();
          expect(
            a.walk.lastObservation,
            orderedEquals(b.walk.lastObservation!),
          );
          expect(
            ah.nextAction.values.take(12),
            orderedEquals(bh.nextAction.values.take(12)),
          );
          if (i < 55) expect(bh.nextAction.values.skip(12), everyElement(0.0));
          if (a.walk.forceWheelStop) {
            expect(ah.nextAction.values.skip(12), everyElement(0.0));
          } else if (i >= 25 && i < 55) {
            policyWheelsNonZero |= ah.nextAction.values
                .skip(12)
                .any((v) => v.abs() > 1e-4);
          } else if (i >= 55) {
            expect(ah.nextAction.values, orderedEquals(bh.nextAction.values));
          }
        }
        expect(policyWheelsNonZero, isTrue);
        await aSub.cancel();
        aSub = null;
        for (final forceZero in [true, false]) {
          await a.switchProfile(
            standingPose: profile.standingPose,
            sittingPose: profile.sittingPose,
            modelPath: modelPath,
            observationBuilder: profile.toObservationBuilder(),
            forceZeroWheelOnStop: forceZero,
          );
          expect(a.walk.forceZeroWheelOnStop, forceZero);
          expect(a.walk.forceWheelStop, isFalse);
        }
      } finally {
        await aSub?.cancel();
        await bSub?.cancel();
        a.dispose();
        b.dispose();
        await aClock.close();
        await bClock.close();
      }
    },
    skip: !hasFixture,
  );
}
