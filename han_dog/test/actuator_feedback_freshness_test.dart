import 'package:han_dog/han_dog.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

YunZhuoState _ch5(GSState state) {
  final channels = List<int>.filled(16, SbusValues.low);
  channels[4] = state.value;
  return YunZhuoState(
    L1: false,
    L2: false,
    R1: false,
    R2: false,
    leftStick: Vector2.zero(),
    rightStick: Vector2.zero(),
    H: true,
    G_S: state,
    red: false,
    LT: false,
    RT: false,
    knob: 0,
    rawChannels: channels,
  );
}

void main() {
  final epoch = DateTime.utc(2026);

  group('ActuatorFeedbackFreshness', () {
    late DateTime now;
    late ActuatorFeedbackFreshness freshness;

    setUp(() {
      now = epoch;
      freshness = ActuatorFeedbackFreshness(
        maxAge: const Duration(milliseconds: 100),
        clock: () => now,
      );
    });

    test('startup and one missing actuator fail closed', () {
      expect(freshness.allFresh, isFalse);
      for (var index = 0; index < hanDogActuatorCount - 1; index++) {
        freshness.record(index);
      }

      expect(freshness.allFresh, isFalse);
      expect(freshness.unavailableActuatorIndices, <int>[15]);
    });

    test('a whole silent CAN leg fails closed', () {
      const silentLeg = <int>{8, 9, 10, 11};
      for (var index = 0; index < hanDogActuatorCount; index++) {
        if (!silentLeg.contains(index)) freshness.record(index);
      }

      expect(freshness.allFresh, isFalse);
      expect(freshness.unavailableActuatorIndices, silentLeg.toList());
    });

    test('all 16 fresh reports make the gate ready', () {
      for (var index = 0; index < hanDogActuatorCount; index++) {
        freshness.record(index);
      }

      expect(freshness.allFresh, isTrue);
      expect(freshness.unavailableActuatorIndices, isEmpty);
    });

    test('expiry revokes readiness and a complete refresh recovers it', () {
      for (var index = 0; index < hanDogActuatorCount; index++) {
        freshness.record(index);
      }
      expect(freshness.allFresh, isTrue);

      now = now.add(const Duration(milliseconds: 101));
      expect(freshness.allFresh, isFalse);
      expect(
        freshness.unavailableActuatorIndices,
        List<int>.generate(hanDogActuatorCount, (index) => index),
      );

      for (var index = 0; index < hanDogActuatorCount - 1; index++) {
        freshness.record(index);
      }
      expect(freshness.allFresh, isFalse);
      freshness.record(hanDogActuatorCount - 1);
      expect(freshness.allFresh, isTrue);
    });

    test('clock rollback clears readiness until all reports recover', () {
      for (var index = 0; index < hanDogActuatorCount; index++) {
        freshness.record(index);
      }
      expect(freshness.allFresh, isTrue);

      now = now.subtract(const Duration(milliseconds: 1));
      expect(freshness.allFresh, isFalse);
      for (var index = 0; index < hanDogActuatorCount; index++) {
        freshness.record(index);
      }
      expect(freshness.allFresh, isTrue);
    });

    test('CH5 arm admission consumes its gate until all 16 are fresh', () {
      final mode = YunZhuoModeStateMachine()
        ..armAdmission = () => freshness.allFresh;
      DateTime at(int milliseconds) =>
          epoch.add(Duration(milliseconds: milliseconds));

      mode.update(_ch5(GSState.middle), at(0));
      mode.update(_ch5(GSState.middle), at(300));
      mode.update(_ch5(GSState.down), at(301));
      expect(
        mode.update(_ch5(GSState.down), at(401)).mode,
        YunZhuoControlMode.neutral,
      );

      for (var index = 0; index < hanDogActuatorCount; index++) {
        freshness.record(index);
      }
      mode.update(_ch5(GSState.middle), at(402));
      mode.update(_ch5(GSState.middle), at(702));
      mode.update(_ch5(GSState.down), at(703));
      expect(
        mode.update(_ch5(GSState.down), at(803)).mode,
        YunZhuoControlMode.arm,
      );
    });

    test('invalid report slots cannot satisfy the gate', () {
      freshness.record(-1);
      freshness.record(hanDogActuatorCount);
      expect(freshness.allFresh, isFalse);
      expect(freshness.unavailableActuatorIndices, hasLength(16));
    });
  });
}
