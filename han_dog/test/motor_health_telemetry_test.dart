import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

class _MockRealJoint extends Mock implements RealJoint {}

MotorFaultEvent _fault(int jointIndex, double position) => MotorFaultEvent(
  jointIndex: jointIndex,
  errors: {RSError.overTemperature},
  errorBits: 0x04,
  status: RSStatus.motor,
  position: position,
  velocity: position + 1,
  torque: position + 2,
  temperature: 80 + position,
);

void main() {
  test(
    'critical escalation preserves the latest raw motor telemetry',
    () async {
      final joint = _MockRealJoint();
      final faults = StreamController<MotorFaultEvent>.broadcast();
      when(() => joint.motorFaultStream).thenAnswer((_) => faults.stream);
      final manager = MotorHealthManager(joint: joint, requestFault: (_) {});
      final emitted = <MotorHealthEvent>[];
      final subscription = manager.healthStream.listen(emitted.add);

      for (var attempt = 0; attempt < 3; attempt++) {
        faults.add(_fault(0, 0.25));
      }
      for (var attempt = 0; attempt < 3; attempt++) {
        faults.add(_fault(1, 0.5));
      }
      await Future<void>.delayed(Duration.zero);

      final escalated = emitted.lastWhere(
        (event) =>
            event.jointIndex == 0 && event.severity == MotorSeverity.critical,
      );
      expect(escalated.errorBits, 0x04);
      expect(escalated.status, RSStatus.motor);
      expect(escalated.position, 0.25);
      expect(escalated.velocity, 1.25);
      expect(escalated.torque, 2.25);
      expect(escalated.temperature, 80.25);

      await subscription.cancel();
      manager.dispose();
      await faults.close();
    },
  );
}
