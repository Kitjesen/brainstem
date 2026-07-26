import 'dart:math' as math;

import 'package:han_dog/han_dog.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

final startAction = JointsMatrix.fromList(
  List<double>.generate(16, (index) => index / 10),
);
final policyAction = JointsMatrix.fromList(
  List<double>.generate(16, (index) => 1.5 - index / 20),
);
final standKp = JointsMatrix.fromList(List<double>.filled(16, 200));
final standKd = JointsMatrix.fromList(List<double>.filled(16, 8));
final inferKp = JointsMatrix.fromList(List<double>.filled(16, 100));
final inferKd = JointsMatrix.fromList(List<double>.filled(16, 15));

BodyHeightHandover buildHandover() => BodyHeightHandover(
  standUpKp: standKp,
  standUpKd: standKd,
  inferKp: inferKp,
  inferKd: inferKd,
);

JointsMatrix _withZeroWheels(List<double> legs) =>
    JointsMatrix.fromList([...legs, 0.0, 0.0, 0.0, 0.0]);

double _maxAbsDifference(JointsMatrix left, JointsMatrix right) {
  var result = 0.0;
  for (var index = 0; index < left.values.length; index++) {
    result = math.max(result, (left.values[index] - right.values[index]).abs());
  }
  return result;
}

void main() {
  test('frame 0, 50, and 100 share one smoothstep for action and gains', () {
    final handover = buildHandover();
    handover.requestFrom(startAction);
    handover.begin();

    final frame0 = handover.preview(policyAction);
    expect(frame0.frameIndex, 0);
    expect(frame0.alpha, 0.0);
    expect(frame0.action.values, startAction.discardFoot().values);
    expect(frame0.kp.values, standKp.values);
    expect(frame0.kd.values, standKd.values);

    for (var index = 0; index < 50; index++) {
      handover.markApplied();
    }
    final frame50 = handover.preview(policyAction);
    expect(frame50.frameIndex, 50);
    expect(frame50.alpha, closeTo(0.5, 1e-12));
    expect(
      frame50.action.values[12],
      closeTo(policyAction.values[12] * 0.5, 1e-12),
    );
    expect(frame50.kp.values[0], closeTo(150, 1e-12));
    expect(frame50.kd.values[0], closeTo(11.5, 1e-12));

    for (var index = 50; index < 100; index++) {
      handover.markApplied();
    }
    final frame100 = handover.preview(policyAction);
    expect(frame100.frameIndex, 100);
    expect(frame100.alpha, 1.0);
    expect(frame100.action.values, policyAction.values);
    expect(frame100.kp.values, inferKp.values);
    expect(frame100.kd.values, inferKd.values);

    handover.markApplied();
    expect(handover.blocksControllerCommands, isFalse);
  });

  test('preview without an applied send never advances', () {
    final handover = buildHandover()
      ..requestFrom(startAction)
      ..begin();

    expect(handover.preview(policyAction).frameIndex, 0);
    expect(handover.preview(policyAction).frameIndex, 0);
  });

  test('disable suspends and re-enable restarts at a fresh measured pose', () {
    final handover = buildHandover()
      ..requestFrom(startAction)
      ..begin();
    handover.markApplied();
    handover.suspend();

    expect(handover.isSuspended, isTrue);
    final fresh = JointsMatrix.fromList(List<double>.filled(16, 0.25));
    handover.restartFrom(fresh);
    final restarted = handover.preview(policyAction);

    expect(restarted.frameIndex, 0);
    expect(restarted.action.values, fresh.discardFoot().values);
  });

  test('request captures qStart before Walking is confirmed', () {
    final handover = buildHandover();
    handover.requestFrom(startAction);

    final laterMeasurement = JointsMatrix.fromList(
      List<double>.filled(16, 0.75),
    );
    handover.begin();
    final frame0 = handover.preview(policyAction);

    expect(frame0.action.values, startAction.discardFoot().values);
    expect(frame0.action.values, isNot(laterMeasurement.discardFoot().values));
  });

  test('disable can suspend a request before Walking confirmation', () {
    final handover = buildHandover();
    handover.requestFrom(startAction);

    handover.suspend();

    expect(handover.isSuspended, isTrue);
    expect(handover.blocksControllerCommands, isTrue);
  });

  test(
    'captured first frame has no jump and policy correction stays bounded',
    () {
      const qStartLegs = <double>[
        -0.007864,
        -0.838384,
        1.718005,
        0.009015,
        0.838000,
        -1.699976,
        0.016304,
        0.833397,
        -1.712635,
        -0.016687,
        -0.839151,
        1.716855,
      ];
      const qPolicyLegs = <double>[
        0.045852,
        -0.674532,
        1.654495,
        0.101351,
        0.842166,
        -1.876151,
        -0.138215,
        0.859309,
        -1.745764,
        -0.079694,
        -0.971636,
        1.921697,
      ];
      final qStart = _withZeroWheels(qStartLegs);
      final qPolicy = _withZeroWheels(qPolicyLegs);
      final handover = buildHandover()
        ..requestFrom(qStart)
        ..begin();

      final frame0 = handover.preview(qPolicy);
      expect(_maxAbsDifference(frame0.action, qStart), 0);

      for (var index = 0; index < BodyHeightHandover.intervalCount; index++) {
        handover.markApplied();
      }
      final frame100 = handover.preview(qPolicy);
      expect(_maxAbsDifference(frame100.action, qPolicy), lessThan(1e-12));
      expect(_maxAbsDifference(qStart, qPolicy), lessThanOrEqualTo(0.25));
    },
  );

  test('invalid phase transitions fail closed', () {
    final handover = buildHandover();

    expect(handover.begin, throwsStateError);
    expect(() => handover.preview(policyAction), throwsStateError);
    expect(handover.markApplied, throwsStateError);
    expect(() => handover.restartFrom(startAction), throwsStateError);
  });
}
