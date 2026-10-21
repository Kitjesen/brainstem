import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

class MockCan extends Mock implements PcanController<RSEvent, RSState> {}

RSState report(int id, {bool enabled = false}) => RSState.report(
  hostId: 255,
  canId: id,
  status: enabled ? RSStatus.motor : RSStatus.reset,
  position: 0,
  velocity: 0,
  torque: 0,
  temperature: 26,
  errors: RSErrors1(0),
);

void main() {
  setUpAll(() => registerFallbackValue(RSEvent.disable(1)));
  test(
    'disable retries a lost stop and confirms all fresh motor reports',
    () async {
      final feeds = List.generate(
        4,
        (_) => StreamController<RSState>.broadcast(),
      );
      final stops = List.generate(4, (_) => List.filled(4, 0));
      final pcans = List.generate(4, (leg) {
        final p = MockCan();
        when(() => p.state).thenAnswer((_) => feeds[leg].stream);
        when(() => p.add(any())).thenAnswer((call) {
          if (call.positionalArguments.single case RSEventDisable(
            :final canId,
          )) {
            stops[leg][canId - 1]++;
          }
        });
        return p;
      });
      final joint = RealJoint.withControllers(pcans);
      final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        for (var leg = 0; leg < 4; leg++) {
          for (var id = 1; id <= 4; id++) {
            feeds[leg].add(
              report(
                id,
                enabled: leg == 3 && id == 4 && stops[leg][id - 1] < 3,
              ),
            );
          }
        }
      });
      try {
        final stopping = joint.disable();
        await expectLater(joint.enable(), throwsStateError);
        await stopping;
        expect(joint.lastDisableConfirmed, isTrue);
        expect(stops[3][3], greaterThanOrEqualTo(3));
        expect(joint.unconfirmedDisableJoints, isEmpty);
      } finally {
        timer.cancel();
        joint.dispose();
        for (final f in feeds) {
          await f.close();
        }
      }
    },
  );
  test(
    'stale zero status cannot confirm disable; timeout blocks re-enable',
    () async {
      final feeds = List.generate(
        4,
        (_) => StreamController<RSState>.broadcast(),
      );
      final pcans = List.generate(4, (i) {
        final p = MockCan();
        when(() => p.state).thenAnswer((_) => feeds[i].stream);
        return p;
      });
      final joint = RealJoint.withControllers(pcans);
      for (final f in feeds) {
        for (var id = 1; id <= 4; id++) {
          f.add(report(id));
        }
      }
      await Future<void>.delayed(Duration.zero);
      try {
        await joint.disable();
        expect(joint.lastDisableConfirmed, isFalse);
        expect(joint.unconfirmedDisableJoints, hasLength(16));
        await expectLater(joint.enable(), throwsStateError);
      } finally {
        joint.dispose();
        for (final f in feeds) {
          await f.close();
        }
      }
    },
  );
}
