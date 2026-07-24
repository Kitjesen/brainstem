import 'dart:async';

import 'package:frequency_watch/frequency_watch.dart';
import 'package:han_dog/han_dog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

class _MockPcanController extends Mock
    implements PcanController<RSEvent, RSState> {}

RSStateReport _report({
  required int canId,
  RSStatus status = RSStatus.motor,
  double position = 0,
  double velocity = 0,
  double torque = 0,
  double temperature = 25,
  int errorBits = 0,
}) =>
    RSState.report(
          hostId: 0xff,
          canId: canId,
          status: status,
          position: position,
          velocity: velocity,
          torque: torque,
          temperature: temperature,
          errors: RSErrors1(errorBits),
        )
        as RSStateReport;

void main() {
  late List<_MockPcanController> pcans;
  late List<StreamController<RSState>> states;

  setUpAll(() {
    registerFallbackValue(RSEvent.disable(1));
    RealFrequency.manager.watch();
  });

  tearDownAll(RealFrequency.manager.dispose);

  setUp(() {
    pcans = List.generate(4, (_) => _MockPcanController());
    states = List.generate(4, (_) => StreamController<RSState>.broadcast());
    for (var i = 0; i < pcans.length; i++) {
      when(() => pcans[i].state).thenAnswer((_) => states[i].stream);
      when(() => pcans[i].open()).thenReturn(true);
      when(() => pcans[i].add(any())).thenReturn(null);
      when(() => pcans[i].close()).thenReturn(null);
    }
  });

  tearDown(() async {
    for (final state in states) {
      await state.close();
    }
  });

  RealJoint buildJoint({required bool commandsAllowed}) =>
      RealJoint.withControllers(
        pcans,
        motorEnableAllowed: () => commandsAllowed,
      );

  Future<void> publishHealthyReports() async {
    for (var leg = 0; leg < states.length; leg++) {
      for (var canId = 1; canId <= 4; canId++) {
        states[leg].add(_report(canId: canId));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 1100));
  }

  group('motor authorization', () {
    test('denied enable sends disable and throws', () async {
      final joint = buildJoint(commandsAllowed: false);

      await expectLater(joint.enable(), throwsStateError);

      for (final pcan in pcans) {
        final sent = verify(() => pcan.add(captureAny())).captured;
        expect(sent, [
          RSEvent.disable(1),
          RSEvent.disable(2),
          RSEvent.disable(3),
          RSEvent.disable(4),
        ]);
      }
    });

    test('denied authorization drops policy action frames', () {
      final joint = buildJoint(commandsAllowed: false);

      joint.sendAction(JointsMatrix.zero());

      for (final pcan in pcans) {
        verifyNever(() => pcan.add(any()));
      }
    });
  });

  group('startup fail-safe', () {
    test('each opened channel is disabled before opening the next one', () {
      final joint = buildJoint(commandsAllowed: false);

      expect(joint.open(), isTrue);

      verifyInOrder([
        () => pcans[0].open(),
        () => pcans[0].add(RSEvent.disable(1)),
        () => pcans[0].add(RSEvent.disable(2)),
        () => pcans[0].add(RSEvent.disable(3)),
        () => pcans[0].add(RSEvent.disable(4)),
        () => pcans[1].open(),
      ]);
    });

    test('a failed channel is never sent startup commands', () {
      when(() => pcans[1].open()).thenReturn(false);
      final joint = buildJoint(commandsAllowed: false);

      expect(joint.open(), isFalse);

      verifyNever(() => pcans[1].add(any()));
      verify(() => pcans[0].add(any())).called(4);
    });
  });

  group('enable preflight', () {
    test('offline motors block enable', () {
      final joint = buildJoint(commandsAllowed: true);

      expect(joint.motorEnableBlockReason(), contains('offline joints'));
    });

    test('flat foot index uses the correct leg CAN frequency', () async {
      final joint = buildJoint(commandsAllowed: true);
      states[0].add(_report(canId: 4));
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(joint.isOnline(12), isTrue);
      expect(joint.isOnline(3), isFalse);
    });

    test('report stream exposes JointsMatrix flat IDs', () async {
      final joint = buildJoint(commandsAllowed: true);
      final reported = joint.reportStream.first;

      states[0].add(_report(canId: 4));

      expect((await reported).$1, 12);
    });

    test('healthy reports permit enable', () async {
      final joint = buildJoint(commandsAllowed: true);
      await publishHealthyReports();

      expect(joint.motorEnableBlockReason(), isNull);
      await joint.enable();
      for (final pcan in pcans) {
        final sent = verify(() => pcan.add(captureAny())).captured;
        expect(sent, [
          RSEvent.enable(1),
          RSEvent.enable(2),
          RSEvent.enable(3),
          RSEvent.enable(4),
        ]);
      }
    });

    test(
      'fault, unsafe status, invalid pose, or non-finite telemetry block',
      () async {
        final joint = buildJoint(commandsAllowed: true);
        await publishHealthyReports();
        states[0].add(
          _report(
            canId: 1,
            status: RSStatus.calibration,
            position: 3.2,
            velocity: double.nan,
            errorBits: 1,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final reason = joint.motorEnableBlockReason();
        expect(reason, contains('unsafe joints'));
        expect(reason, contains('status='));
        expect(reason, contains('errors='));
        expect(reason, contains('position='));
        expect(reason, contains('non-finite velocity/torque'));
      },
    );

    test('non-finite wheel position or temperature blocks enable', () async {
      final joint = buildJoint(commandsAllowed: true);
      await publishHealthyReports();
      states[0].add(
        _report(canId: 4, position: double.nan, temperature: double.infinity),
      );
      await Future<void>.delayed(Duration.zero);

      final reason = joint.motorEnableBlockReason();
      expect(reason, contains('position='));
      expect(reason, contains('temperature='));
    });
  });
}
