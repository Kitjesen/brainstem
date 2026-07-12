import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

class _MockRealJoint extends Mock implements RealJoint {}

void main() {
  late _MockRealJoint joint;
  late StreamController<MotorFaultEvent> faults;

  setUp(() {
    joint = _MockRealJoint();
    faults = StreamController<MotorFaultEvent>.broadcast();
    when(() => joint.motorFaultStream).thenAnswer((_) => faults.stream);
    when(() => joint.isOnline(any())).thenReturn(true);
    when(() => joint.getReport(any())).thenReturn(null);
  });

  tearDown(() async {
    await faults.close();
  });

  void emitCriticalFaults() {
    for (var i = 0; i < 3; i++) {
      faults.add(
        const MotorFaultEvent(
          jointIndex: 0,
          errors: {RSError.driverFault},
          errorBits: 0,
          status: RSStatus.motor,
          position: 0,
          velocity: 0,
          torque: 0,
          temperature: 25,
        ),
      );
    }
  }

  test(
    'a critical motor fault sends Disable through the shared output',
    () async {
      when(
        () => joint.disable(clearErrors: any(named: 'clearErrors')),
      ).thenAnswer((_) async {});
      final output = MotorOutputController(motor: joint);
      final health = MotorHealthManager(
        joint: joint,
        requestFault: (_) {},
        motorOutput: output,
      );

      emitCriticalFaults();
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.disable(clearErrors: false)).called(1);
      expect(health.hasFaults, isTrue);
      health.dispose();
    },
  );

  test('degraded health is published after recovery becomes pending', () async {
    final health = MotorHealthManager(joint: joint, requestFault: (_) {});
    final recoveryPendingAtDegraded = <bool>[];
    final StreamSubscription<MotorHealthEvent> subscription = health
        .healthStream
        .where((event) => event.severity == MotorSeverity.degraded)
        .listen((_) => recoveryPendingAtDegraded.add(health.hasFaults));

    for (var i = 0; i < 3; i++) {
      faults.add(
        const MotorFaultEvent(
          jointIndex: 0,
          errors: {RSError.overTemperature},
          errorBits: 0,
          status: RSStatus.motor,
          position: 0,
          velocity: 0,
          torque: 0,
          temperature: 25,
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(recoveryPendingAtDegraded, <bool>[true]);
    expect(health.hasFaults, isTrue);
    await subscription.cancel();
    health.dispose();
  });

  test(
    'recovery does not clear a joint when Disable CAN request fails',
    () async {
      when(
        () => joint.disable(clearErrors: any(named: 'clearErrors')),
      ).thenThrow(StateError('CAN disable not confirmed'));
      final output = MotorOutputController(motor: joint);
      final health = MotorHealthManager(
        joint: joint,
        requestFault: (_) {},
        motorOutput: output,
      );

      emitCriticalFaults();
      await Future<void>.delayed(Duration.zero);
      await health.recoverFaults();

      verifyNever(() => joint.clearFaultSingle(any()));
      expect(health.hasFaults, isTrue);
      health.dispose();
    },
  );
}
