import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

YunZhuoState _state(
  GSState gs, {
  Vector2? left,
  Vector2? right,
  double knob = 0,
  bool lt = false,
  bool rt = false,
}) {
  final channels = List<int>.filled(16, SbusValues.low);
  channels[4] = gs.value;
  return YunZhuoState(
    L1: false,
    L2: false,
    R1: false,
    R2: false,
    leftStick: left ?? Vector2.zero(),
    rightStick: right ?? Vector2.zero(),
    H: true,
    G_S: gs,
    red: false,
    LT: lt,
    RT: rt,
    knob: knob,
    rawChannels: channels,
  );
}

void main() {
  final epoch = DateTime.utc(2026);
  DateTime at(int milliseconds) =>
      epoch.add(Duration(milliseconds: milliseconds));

  group('YunZhuoControlMode', () {
    test('cold startup requires a fresh centered neutral cycle', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => true;

      expect(
        machine.update(_state(GSState.up), at(0)).mode,
        YunZhuoControlMode.neutral,
      );
      expect(
        machine.update(_state(GSState.up), at(500)).mode,
        YunZhuoControlMode.neutral,
      );

      machine.update(_state(GSState.middle), at(501));
      machine.update(_state(GSState.middle), at(801));
      machine.update(_state(GSState.up), at(802));
      final dog = machine.update(_state(GSState.up), at(902));
      expect(dog.mode, YunZhuoControlMode.dog);
      expect(dog.modeChanged, isTrue);
    });

    test(
      'cold startup never accepts an upper detent with displaced sticks',
      () {
        final machine = YunZhuoModeStateMachine()..armAdmission = () => true;

        machine.update(_state(GSState.up, left: Vector2(0, 0.5)), at(0));
        expect(
          machine
              .update(_state(GSState.up, left: Vector2(0, 0.5)), at(500))
              .mode,
          YunZhuoControlMode.neutral,
        );
        expect(
          machine.update(_state(GSState.up), at(501)).mode,
          YunZhuoControlMode.neutral,
        );
        expect(
          machine.update(_state(GSState.up), at(600)).mode,
          YunZhuoControlMode.neutral,
        );
        expect(
          machine.update(_state(GSState.up), at(1000)).mode,
          YunZhuoControlMode.neutral,
        );
      },
    );

    test('startup down never inherits arm and must use the neutral gate', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => true;

      machine.update(_state(GSState.down), at(0));
      expect(
        machine.update(_state(GSState.down), at(500)).mode,
        YunZhuoControlMode.neutral,
      );
      machine.update(_state(GSState.up), at(501));
      expect(
        machine.update(_state(GSState.up), at(700)).mode,
        YunZhuoControlMode.neutral,
      );

      machine.update(_state(GSState.middle), at(701));
      final ready = machine.update(_state(GSState.middle), at(1001));
      expect(ready.neutralGateReady, isTrue);

      machine.update(_state(GSState.up), at(1002));
      final dog = machine.update(_state(GSState.up), at(1102));
      expect(dog.mode, YunZhuoControlMode.dog);
    });

    test('fast sweep dog to arm is locked in neutral', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => true;
      machine.update(_state(GSState.middle), at(0));
      machine.update(_state(GSState.middle), at(300));
      machine.update(_state(GSState.up), at(301));
      machine.update(_state(GSState.up), at(401));

      machine.update(_state(GSState.middle), at(500));
      machine.update(_state(GSState.down), at(550));
      final result = machine.update(_state(GSState.down), at(650));

      expect(result.mode, YunZhuoControlMode.neutral);
      expect(result.neutralGateReady, isFalse);
    });

    test('arm admission rejection consumes the neutral gate', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => false;
      machine.update(_state(GSState.middle), at(0));
      machine.update(_state(GSState.middle), at(300));
      machine.update(_state(GSState.down), at(301));
      final rejected = machine.update(_state(GSState.down), at(401));

      expect(rejected.mode, YunZhuoControlMode.neutral);
      expect(rejected.neutralGateReady, isFalse);
    });

    test('moving a stick while leaving neutral consumes the gate', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => true;
      machine.update(_state(GSState.middle), at(0));
      expect(
        machine.update(_state(GSState.middle), at(300)).neutralGateReady,
        isTrue,
      );

      machine.update(_state(GSState.down, left: Vector2(0.5, 0)), at(301));
      final rejected = machine.update(
        _state(GSState.down, left: Vector2(0.5, 0)),
        at(401),
      );
      expect(rejected.mode, YunZhuoControlMode.neutral);
      expect(rejected.neutralGateReady, isFalse);

      // 在目标档重新居中不恢复已消费的门槛。
      expect(
        machine.update(_state(GSState.down), at(500)).mode,
        YunZhuoControlMode.neutral,
      );
      machine.update(_state(GSState.middle), at(501));
      machine.update(_state(GSState.middle), at(801));
      machine.update(_state(GSState.down), at(802));
      expect(
        machine.update(_state(GSState.down), at(902)).mode,
        YunZhuoControlMode.arm,
      );
    });

    test('dog exit can only be cancelled during the 400ms ramp', () {
      YunZhuoModeStateMachine dogMachine() {
        final machine = YunZhuoModeStateMachine()..armAdmission = () => true;
        machine.update(_state(GSState.middle), at(0));
        machine.update(_state(GSState.middle), at(300));
        machine.update(_state(GSState.up), at(301));
        machine.update(_state(GSState.up), at(401));
        return machine;
      }

      final duringRamp = dogMachine();
      duringRamp.update(_state(GSState.middle, left: Vector2(0.5, 0)), at(500));
      duringRamp.update(_state(GSState.middle, left: Vector2(0.5, 0)), at(600));
      duringRamp.update(_state(GSState.up, left: Vector2(0.5, 0)), at(650));
      expect(
        duringRamp
            .update(_state(GSState.up, left: Vector2(0.5, 0)), at(750))
            .mode,
        YunZhuoControlMode.dog,
      );

      final afterRamp = dogMachine();
      afterRamp.update(_state(GSState.middle, left: Vector2(0.5, 0)), at(500));
      afterRamp.update(_state(GSState.middle, left: Vector2(0.5, 0)), at(600));
      afterRamp.update(_state(GSState.up, left: Vector2(0.5, 0)), at(1100));
      expect(
        afterRamp
            .update(_state(GSState.up, left: Vector2(0.5, 0)), at(1200))
            .mode,
        YunZhuoControlMode.neutral,
      );
    });

    test('leaving arm is immediate, before 100ms debounce', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => true;
      machine.update(_state(GSState.middle), at(0));
      machine.update(_state(GSState.middle), at(300));
      machine.update(_state(GSState.down), at(301));
      expect(
        machine.update(_state(GSState.down), at(401)).mode,
        YunZhuoControlMode.arm,
      );

      expect(
        machine.update(_state(GSState.middle), at(402)).mode,
        YunZhuoControlMode.neutral,
      );
    });

    test('input loss reset requires a fresh centered neutral cycle', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => true;
      machine.update(_state(GSState.middle), at(0));
      machine.update(_state(GSState.middle), at(300));
      machine.update(_state(GSState.up), at(301));
      expect(
        machine.update(_state(GSState.up), at(401)).mode,
        YunZhuoControlMode.dog,
      );
      machine.update(_state(GSState.up, left: Vector2(0, 1)), at(402));

      machine.resetForInputLoss();
      expect(
        machine.update(_state(GSState.up, left: Vector2(0, 1)), at(1000)).mode,
        YunZhuoControlMode.neutral,
      );
      expect(
        machine.update(_state(GSState.up, left: Vector2(0, 1)), at(1200)).mode,
        YunZhuoControlMode.neutral,
      );

      machine.update(_state(GSState.middle), at(1300));
      machine.update(_state(GSState.middle), at(1600));
      machine.update(_state(GSState.up), at(1601));
      expect(
        machine.update(_state(GSState.up), at(1701)).mode,
        YunZhuoControlMode.dog,
      );
    });

    test('an injected clock rollback fails closed to neutral', () {
      final machine = YunZhuoModeStateMachine()..armAdmission = () => true;
      machine.update(_state(GSState.middle), at(0));
      machine.update(_state(GSState.middle), at(300));
      machine.update(_state(GSState.up), at(301));
      expect(
        machine.update(_state(GSState.up), at(401)).mode,
        YunZhuoControlMode.dog,
      );

      final rolledBack = machine.update(
        _state(GSState.up, left: Vector2(0, 1)),
        at(100),
      );
      expect(rolledBack.mode, YunZhuoControlMode.neutral);
      expect(rolledBack.dogDriveScale, 0.0);
      expect(rolledBack.neutralGateReady, isFalse);
    });
  });

  test('dog yaw uses CH14 knob and ignores right-stick X', () {
    final a = mapYunZhuoDogDirection(
      _state(GSState.up, right: Vector2(1, 0), knob: 0.25),
    );
    final b = mapYunZhuoDogDirection(
      _state(GSState.up, right: Vector2(-1, 0), knob: 0.25),
    );

    expect(a.z, closeTo(-0.25, 1e-12));
    expect(b.z, closeTo(a.z, 1e-12));
  });

  test('LT and RT scale translation but never CH14 yaw', () {
    final normal = mapYunZhuoDogDirection(
      _state(GSState.up, left: Vector2(0.4, 0.6), knob: 0.8),
    );
    final precise = mapYunZhuoDogDirection(
      _state(GSState.up, left: Vector2(0.4, 0.6), knob: 0.8, lt: true),
    );
    final sprint = mapYunZhuoDogDirection(
      _state(GSState.up, left: Vector2(0.4, 0.6), knob: 0.8, rt: true),
    );

    expect(precise.x, closeTo(normal.x * 0.5, 1e-12));
    expect(sprint.x, closeTo(normal.x * 1.5, 1e-12));
    expect(normal.z, closeTo(-0.8, 1e-7));
    expect(precise.z, closeTo(normal.z, 1e-12));
    expect(sprint.z, closeTo(normal.z, 1e-12));
  });

  test(
    'red emits initial held and later rising edges, never release',
    () async {
      final states = StreamController<bool>();
      final events = <bool>[];
      final subscription = redButtonPressEvents(
        states.stream,
      ).listen(events.add);

      states.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(events, <bool>[true]);

      states.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(events, <bool>[true]);

      states.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(events, <bool>[true, true]);

      await states.close();
      await subscription.cancel();
    },
  );
}
