import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockBrain extends Mock implements Brain {}

class MockArbiter extends Mock implements ControlArbiter {}

class MockRealImu extends Mock implements RealImu {}

class MockRealJoint extends Mock implements RealJoint {}

class MockGamepad extends Mock implements Gamepad {}

class MockRealController extends Mock implements RealController {
  MockRealController() {
    when(() => hardStopActive).thenReturn(false);
  }
}

void main() {
  late MockBrain brain;
  late MockArbiter arbiter;
  late MockRealImu imu;
  late MockRealJoint joint;
  late MockGamepad controller;

  // StreamControllers for each controller stream
  late StreamController<Vector3> directionCtrl;
  late StreamController<bool> standupCtrl;
  late StreamController<bool> sitdownCtrl;
  late StreamController<bool> idleCtrl;
  late StreamController<bool> redCtrl;
  late StreamController<bool> enabledCtrl;
  late StreamController<void> calibrateCtrl;
  late StreamController<void> switchProfileCtrl;
  late StreamController<S> stateCtrl;
  var commandTime = DateTime.utc(2026);

  Future<void> emitDirection(Vector3 target, [int frames = 1]) async {
    for (var i = 0; i < frames; i++) {
      commandTime = commandTime.add(const Duration(milliseconds: 10));
      directionCtrl.add(target);
      await Future<void>.delayed(Duration.zero);
    }
  }

  final inferKp = JointsMatrix.fromList(List.filled(16, 1.0));
  final inferKd = JointsMatrix.fromList(List.filled(16, 2.0));
  final standUpKp = JointsMatrix.fromList(List.filled(16, 3.0));
  final standUpKd = JointsMatrix.fromList(List.filled(16, 4.0));
  final sitDownKp = JointsMatrix.fromList(List.filled(16, 5.0));
  final sitDownKd = JointsMatrix.fromList(List.filled(16, 6.0));

  setUpAll(() {
    registerFallbackValue(const A.init());
    registerFallbackValue(ControlSource.yunzhuo);
    registerFallbackValue(Vector3.zero());
    registerFallbackValue(JointsMatrix.zero());
  });

  RealControlDog buildDog({
    Gamepad? gamepad,
    Future<void> Function()? requestMotorEnable,
  }) {
    return RealControlDog(
      brain: brain,
      arbiter: arbiter,
      imu: imu,
      joint: joint,
      controller: gamepad ?? controller,
      requestMotorEnable: requestMotorEnable,
      inferKp: inferKp,
      inferKd: inferKd,
      standUpKp: standUpKp,
      standUpKd: standUpKd,
      sitDownKp: sitDownKp,
      sitDownKd: sitDownKd,
      commandClock: () => commandTime,
    );
  }

  setUp(() {
    commandTime = DateTime.utc(2026);
    brain = MockBrain();
    arbiter = MockArbiter();
    imu = MockRealImu();
    joint = MockRealJoint();
    controller = MockGamepad();

    directionCtrl = StreamController<Vector3>.broadcast();
    standupCtrl = StreamController<bool>.broadcast();
    sitdownCtrl = StreamController<bool>.broadcast();
    idleCtrl = StreamController<bool>.broadcast();
    redCtrl = StreamController<bool>.broadcast();
    enabledCtrl = StreamController<bool>.broadcast();
    calibrateCtrl = StreamController<void>.broadcast();
    switchProfileCtrl = StreamController<void>.broadcast();
    stateCtrl = StreamController<S>.broadcast();

    when(() => controller.direction).thenAnswer((_) => directionCtrl.stream);
    when(() => controller.standup).thenAnswer((_) => standupCtrl.stream);
    when(() => controller.sitdown).thenAnswer((_) => sitdownCtrl.stream);
    when(() => controller.idle).thenAnswer((_) => idleCtrl.stream);
    when(() => controller.red).thenAnswer((_) => redCtrl.stream);
    when(() => controller.enabled).thenAnswer((_) => enabledCtrl.stream);
    when(() => controller.calibrate).thenAnswer((_) => calibrateCtrl.stream);
    when(
      () => controller.switchProfile,
    ).thenAnswer((_) => switchProfileCtrl.stream);

    when(() => joint.enable()).thenAnswer((_) async {});
    when(() => joint.disable()).thenAnswer((_) async {});
    when(() => joint.disable(clearErrors: true)).thenAnswer((_) async {});
    when(() => joint.velocity).thenReturn(JointsMatrix.zero());
    when(() => imu.gyroscope).thenReturn(Vector3.zero());

    when(() => arbiter.stateStream).thenAnswer((_) => stateCtrl.stream);
    when(() => arbiter.isHandlingEvent).thenReturn(false);
    when(() => arbiter.profileSwitchInProgress).thenReturn(false);
    when(() => arbiter.state).thenReturn(const Zero());
    when(() => arbiter.command(any(), any())).thenReturn(true);
    when(() => arbiter.fault(any())).thenReturn(null);
  });

  tearDown(() {
    directionCtrl.close();
    standupCtrl.close();
    sitdownCtrl.close();
    idleCtrl.close();
    redCtrl.close();
    enabledCtrl.close();
    calibrateCtrl.close();
    switchProfileCtrl.close();
    stateCtrl.close();
  });

  group('kp/kd switching', () {
    test('Walking → inferKp with Hip-only Kd scale', () async {
      buildDog();
      stateCtrl.add(Walking(Stream<History>.empty().listen((_) {})));
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.kpExt = inferKp).called(1);
      final expectedKd = applyThunderWalkingHipKdScale(inferKd);
      verify(
        () => joint.kdExt = any(
          that: isA<JointsMatrix>().having(
            (matrix) => matrix.values,
            'values',
            expectedKd.values,
          ),
        ),
      ).called(1);
    });

    test('Transitioning(StandUp) → standUpKp/standUpKd', () async {
      buildDog();
      stateCtrl.add(
        Transitioning(
          const Command.standUp(),
          Stream<History>.empty().listen((_) {}),
          null,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.kpExt = standUpKp).called(1);
      verify(() => joint.kdExt = standUpKd).called(1);
    });

    test('Transitioning(SitDown) → sitDownKp/sitDownKd', () async {
      buildDog();
      stateCtrl.add(
        Transitioning(
          const Command.sitDown(),
          Stream<History>.empty().listen((_) {}),
          null,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.kpExt = sitDownKp).called(1);
      verify(() => joint.kdExt = sitDownKd).called(1);
    });

    test('Standing/Grounded/Zero → no kp/kd change', () async {
      buildDog();
      stateCtrl.add(Standing(Stream<History>.empty().listen((_) {})));
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => joint.kpExt = any());
      verifyNever(() => joint.kdExt = any());
    });
  });

  group('direction → walk', () {
    test('non-zero direction → arbiter.command(A.walk, yunzhuo)', () async {
      buildDog();
      await emitDirection(Vector3(1, 0, 0));

      verify(
        () => arbiter.command(any(that: isA<CmdWalk>()), ControlSource.yunzhuo),
      ).called(1);
    });
  });

  test(
    'RealController uses direction directly without CH5 mode routing',
    () async {
      final realController = MockRealController();
      final directions = StreamController<Vector3>.broadcast(sync: true);
      final hardStops = StreamController<void>.broadcast(sync: true);
      when(() => realController.direction).thenAnswer((_) => directions.stream);
      when(() => realController.hardStop).thenAnswer((_) => hardStops.stream);
      when(
        () => realController.standup,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => realController.sitdown,
      ).thenAnswer((_) => const Stream.empty());
      when(() => realController.idle).thenAnswer((_) => const Stream.empty());
      when(() => realController.red).thenAnswer((_) => const Stream.empty());
      when(
        () => realController.enabled,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => realController.calibrate,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => realController.switchProfile,
      ).thenAnswer((_) => const Stream.empty());

      final dog = buildDog(gamepad: realController);
      directions.add(Vector3(0, 1, 0));
      await Future<void>.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(
            that: isA<CmdWalk>().having(
              (command) => command.direction.y,
              'lateral command',
              isNot(0),
            ),
          ),
          ControlSource.yunzhuo,
        ),
      ).called(1);

      when(
        () => arbiter.state,
      ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
      hardStops.add(null);
      verify(
        () => arbiter.command(
          any(
            that: isA<CmdWalk>()
                .having((c) => c.direction, 'hard stop', Vector3.zero())
                .having((c) => c.forceWheelStop, 'force wheels', isTrue),
          ),
          ControlSource.yunzhuo,
        ),
      ).called(1);

      // A synthetic watchdog zero must not clear the hard-stop marker.
      when(() => realController.hardStopActive).thenReturn(true);
      directions.add(Vector3.zero());
      verify(
        () => arbiter.command(
          any(
            that: isA<CmdWalk>().having(
              (c) => c.forceWheelStop,
              'still stopped',
              isTrue,
            ),
          ),
          ControlSource.yunzhuo,
        ),
      ).called(1);

      // Only recovery of real input allows the normal zero-command path.
      when(() => realController.hardStopActive).thenReturn(false);
      directions.add(Vector3.zero());
      verify(
        () => arbiter.command(
          any(
            that: isA<CmdWalk>().having(
              (c) => c.forceWheelStop,
              'normal release',
              isFalse,
            ),
          ),
          ControlSource.yunzhuo,
        ),
      ).called(1);
      dog.dispose();
      await directions.close();
      await hardStops.close();
    },
  );

  group('buttons', () {
    test('L1 → standUp', () async {
      buildDog();
      enabledCtrl.add(true);
      await Future<void>.delayed(Duration.zero);
      standupCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(that: isA<CmdStandUp>()),
          ControlSource.yunzhuo,
        ),
      ).called(1);
    });

    test('L1 while Walking and stick active is ignored', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();
        directionCtrl.add(Vector3(0.5, 0, 0));
        async.flushMicrotasks();

        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        );
        dog.dispose();
      });
    });

    test('L1 while Walking and settled returns to fixed standing', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();

        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 250));
        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        );

        async.elapse(const Duration(milliseconds: 50));
        verify(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        ).called(1);
        dog.dispose();
      });
    });

    test('L1 waits for residual wheel speed to settle', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        when(() => joint.velocity).thenReturn(
          JointsMatrix.fromList(<double>[
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1.2,
            0,
            0,
            0,
          ]),
        );
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();

        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        );

        when(() => joint.velocity).thenReturn(JointsMatrix.zero());
        async.elapse(const Duration(milliseconds: 300));
        verify(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        ).called(1);
        dog.dispose();
      });
    });

    test('L1 rejects a non-finite non-first wheel velocity', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final velocity = List<double>.filled(16, 0)..[13] = double.nan;
        when(() => joint.velocity).thenReturn(JointsMatrix.fromList(velocity));
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();

        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        );
        dog.dispose();
      });
    });

    test('L1 rejects a non-finite non-first gyroscope axis', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        when(() => imu.gyroscope).thenReturn(Vector3(0, double.nan, 0));
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();

        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        );
        dog.dispose();
      });
    });

    test('new walk command cancels pending L1 standUp', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();

        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));
        directionCtrl.add(Vector3(0.5, 0, 0));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        );
        dog.dispose();
      });
    });

    test('L2 → sitDown', () async {
      buildDog();
      sitdownCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(that: isA<CmdSitDown>()),
          ControlSource.yunzhuo,
        ),
      ).called(1);
    });

    test('R1 → standUp', () async {
      buildDog();
      idleCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(that: isA<CmdStandUp>()),
          ControlSource.yunzhuo,
        ),
      ).called(1);
    });

    test('R1 while Walking also waits for the settle gate', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog();

        idleCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 299));
        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        );

        async.elapse(const Duration(milliseconds: 1));
        verify(
          () => arbiter.command(
            any(that: isA<CmdStandUp>()),
            ControlSource.yunzhuo,
          ),
        ).called(1);
        dog.dispose();
      });
    });

    test('red → joint.disable(clearErrors: true)', () async {
      final motorEnableChanges = <bool>[];
      final dog = buildDog()..onMotorEnableChanged = motorEnableChanges.add;
      redCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.disable(clearErrors: true)).called(1);
      expect(motorEnableChanges, <bool>[false]);
      dog.dispose();
    });

    test('enabled true → joint.enable()', () async {
      buildDog();
      enabledCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.enable()).called(1);
    });

    test('enabled false → joint.disable()', () async {
      buildDog();
      enabledCtrl.add(false);
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.disable()).called(1);
    });
  });

  group('L1 enable order', () {
    Future<void> flushInputs() => Future<void>.delayed(Duration.zero);

    void expectNoStandUp() {
      verifyNever(() => arbiter.command(any(that: isA<CmdStandUp>()), any()));
    }

    for (final injected in [false, true]) {
      test(
        'enable pending survives cancellation until ${injected ? 'injected' : 'joint'} request settles',
        () async {
          final pending = Completer<void>();
          when(() => joint.enable()).thenAnswer((_) => pending.future);
          final changes = <bool>[];
          final dog = buildDog(
            requestMotorEnable: injected ? () => pending.future : null,
          )..onMotorEnableChanged = changes.add;
          addTearDown(dog.dispose);
          expect(dog.motorEnablePending, isFalse);
          enabledCtrl.add(true);
          await flushInputs();
          expect(dog.motorEnablePending, isTrue);
          enabledCtrl.add(false);
          await flushInputs();
          expect(changes, [false]);
          expect(dog.motorEnablePending, isTrue);
          pending.complete();
          await flushInputs();
          expect(dog.motorEnablePending, isFalse);
          expect(changes, [false]);
        },
      );
    }

    for (final baseline in [false, true]) {
      test(
        'raw H/L1 baseline $baseline accepts both flips after enable completes',
        () async {
          final raw = StreamController<YunZhuoState>.broadcast();
          final realController = MockRealController();
          final pending = Completer<void>();
          when(() => joint.enable()).thenAnswer((_) => pending.future);
          var allowed = false;
          var generation = 0;
          when(() => realController.setStandUpEnabled(any())).thenAnswer((
            call,
          ) {
            allowed = call.positionalArguments.single as bool;
            generation++;
          });
          when(
            () => realController.direction,
          ).thenAnswer((_) => const Stream.empty());
          when(
            () => realController.hardStop,
          ).thenAnswer((_) => const Stream.empty());
          when(() => realController.standup).thenAnswer(
            (_) => enabledStandUpPresses(
              raw.stream,
              allowed: () => allowed,
              generation: () => generation,
            ),
          );
          when(
            () => realController.enabled,
          ).thenAnswer((_) => raw.stream.map((s) => s.H).distinct());
          when(
            () => realController.sitdown,
          ).thenAnswer((_) => const Stream.empty());
          when(
            () => realController.idle,
          ).thenAnswer((_) => const Stream.empty());
          when(() => realController.red).thenAnswer((_) => redCtrl.stream);
          when(
            () => realController.calibrate,
          ).thenAnswer((_) => const Stream.empty());
          when(
            () => realController.switchProfile,
          ).thenAnswer((_) => const Stream.empty());
          final dog = buildDog(gamepad: realController);
          addTearDown(() async {
            dog.dispose();
            await raw.close();
          });

          Future<void> frame(bool h, bool l1) async {
            raw.add(
              YunZhuoState(
                L1: l1,
                L2: false,
                R1: false,
                R2: false,
                leftStick: Vector2.zero(),
                rightStick: Vector2.zero(),
                H: h,
                G_S: GSState.middle,
                red: false,
                LT: false,
                RT: false,
                knob: 0,
                rawChannels: List<int>.filled(16, SbusValues.center),
              ),
            );
            await flushInputs();
          }

          await frame(false, baseline);
          await frame(false, !baseline);
          expectNoStandUp();
          await frame(true, !baseline);
          expect(allowed, isFalse);
          await frame(true, baseline);
          await frame(true, !baseline);
          expectNoStandUp();
          pending.complete();
          await flushInputs();
          expect(allowed, isTrue);
          expectNoStandUp();
          await frame(true, baseline);
          await frame(true, baseline);
          expectNoStandUp();
          await frame(true, !baseline);
          await frame(true, !baseline);
          verify(
            () => arbiter.command(any(that: isA<CmdStandUp>()), any()),
          ).called(1);
          await frame(true, baseline);
          await frame(true, baseline);
          verify(
            () => arbiter.command(any(that: isA<CmdStandUp>()), any()),
          ).called(1);
          redCtrl.add(true);
          await flushInputs();
          expect(allowed, isFalse);
          await frame(true, false);
          await frame(true, true);
          expectNoStandUp();
        },
      );
    }

    test('startup and disabled L1 are discarded, not replayed by H', () async {
      final dog = buildDog();
      addTearDown(dog.dispose);
      standupCtrl.add(true);
      await flushInputs();
      expectNoStandUp();
      enabledCtrl.add(false);
      await flushInputs();
      standupCtrl.add(true);
      await flushInputs();
      expectNoStandUp();
      enabledCtrl.add(true);
      await flushInputs();
      expectNoStandUp();
      standupCtrl.add(true);
      await flushInputs();
      verify(
        () => arbiter.command(any(that: isA<CmdStandUp>()), any()),
      ).called(1);
    });

    test(
      'L1 during enable is discarded without replay on completion',
      () async {
        final pending = Completer<void>();
        when(() => joint.enable()).thenAnswer((_) => pending.future);
        final dog = buildDog();
        addTearDown(dog.dispose);
        enabledCtrl.add(true);
        await flushInputs();
        standupCtrl.add(true);
        await flushInputs();
        expectNoStandUp();
        pending.complete();
        await flushInputs();
        expectNoStandUp();
        standupCtrl.add(true);
        await flushInputs();
        verify(
          () => arbiter.command(any(that: isA<CmdStandUp>()), any()),
        ).called(1);
      },
    );

    for (final stop in ['H disable', 'red']) {
      test('$stop invalidates an in-flight enable for L1', () async {
        final pending = Completer<void>();
        when(() => joint.enable()).thenAnswer((_) => pending.future);
        final changes = <bool>[];
        final dog = buildDog()..onMotorEnableChanged = changes.add;
        addTearDown(dog.dispose);
        enabledCtrl.add(true);
        await flushInputs();
        if (stop == 'red') {
          redCtrl.add(true);
        } else {
          enabledCtrl.add(false);
        }
        await flushInputs();
        pending.complete();
        await flushInputs();
        standupCtrl.add(true);
        await flushInputs();
        expectNoStandUp();
        expect(changes, [false]);
      });
    }

    for (final failOldEnable in [false, true]) {
      test(
        'stale enable completion ($failOldEnable) cannot arm new H',
        () async {
          final first = Completer<void>();
          final second = Completer<void>();
          var attempts = 0;
          when(
            () => joint.enable(),
          ).thenAnswer((_) => ++attempts == 1 ? first.future : second.future);
          final changes = <bool>[];
          final dog = buildDog()..onMotorEnableChanged = changes.add;
          addTearDown(dog.dispose);
          enabledCtrl.add(true);
          await flushInputs();
          enabledCtrl.add(false);
          await flushInputs();
          enabledCtrl.add(true);
          await flushInputs();
          expect(dog.motorEnablePending, isTrue);
          if (failOldEnable) {
            first.completeError(StateError('old enable failed'));
          } else {
            first.complete();
          }
          await flushInputs();
          expect(dog.motorEnablePending, isTrue);
          standupCtrl.add(true);
          await flushInputs();
          expectNoStandUp();
          expect(changes, [false]);
          second.complete();
          await flushInputs();
          expect(dog.motorEnablePending, isFalse);
          expect(changes, [false, true]);
          standupCtrl.add(true);
          await flushInputs();
          verify(
            () => arbiter.command(any(that: isA<CmdStandUp>()), any()),
          ).called(1);
        },
      );
    }

    test('failed enable does not permit L1', () async {
      when(() => joint.enable()).thenAnswer((_) async {
        throw StateError('enable failed');
      });
      final dog = buildDog();
      addTearDown(dog.dispose);
      enabledCtrl.add(true);
      await flushInputs();
      standupCtrl.add(true);
      await flushInputs();
      expectNoStandUp();
    });

    test('dispose invalidates a late enable completion', () async {
      final pending = Completer<void>();
      when(() => joint.enable()).thenAnswer((_) => pending.future);
      final changes = <bool>[];
      final dog = buildDog()..onMotorEnableChanged = changes.add;
      enabledCtrl.add(true);
      await flushInputs();
      dog.dispose();
      pending.complete();
      await flushInputs();
      expect(changes, isEmpty);
    });

    test('H disable cancels a pending L1 settle request', () {
      fakeAsync((async) {
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();
        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));
        enabledCtrl.add(false);
        async.flushMicrotasks();
        enabledCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expectNoStandUp();
        dog.dispose();
      });
    });
  });

  group('R2 stationary two-mode admission', () {
    Future<void> flush() => Future<void>.delayed(Duration.zero);
    S standing() => Standing(const Stream<History>.empty().listen((_) {}));
    S walking() => Walking(const Stream<History>.empty().listen((_) {}));
    Future<void> finishL1({bool enable = true}) async {
      if (enable) {
        enabledCtrl.add(true);
        await flush();
      }
      final wasWalking = arbiter.state is Walking;
      standupCtrl.add(true);
      await flush();
      if (wasWalking) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      final s = standing();
      when(() => arbiter.state).thenReturn(s);
      stateCtrl.add(s);
      await flush();
    }

    for (final kind in ['walking', 'transitioning', 'standing without L1']) {
      test('$kind R2 is discarded, never replayed on later Standing', () async {
        final dog = buildDog();
        addTearDown(dog.dispose);
        var calls = 0;
        dog.onProfileSwitch = () async {
          calls++;
        };
        final state = switch (kind) {
          'grounded' => Grounded(const Stream<History>.empty().listen((_) {})),
          'walking' => walking(),
          'transitioning' => Transitioning(
            const Command.standUp(),
            const Stream<History>.empty().listen((_) {}),
            null,
          ),
          _ => standing(),
        };
        when(() => arbiter.state).thenReturn(state);
        enabledCtrl.add(true);
        await flush();
        switchProfileCtrl.add(null);
        await flush();
        await finishL1();
        expect(calls, 0);
      });
    }

    test(
      'boot Grounded H R2 selects either slot without L1 or movement',
      () async {
        final dog = buildDog();
        addTearDown(dog.dispose);
        final s = Grounded(const Stream<History>.empty().listen((_) {}));
        when(() => arbiter.state).thenReturn(s);
        var calls = 0;
        dog.onProfileSwitch = () async {
          calls++;
        };
        switchProfileCtrl.add(null);
        await flush();
        expect(calls, 0);
        enabledCtrl.add(true);
        await flush();
        clearInteractions(arbiter);
        for (var i = 0; i < 2; i++) {
          switchProfileCtrl.add(null);
          await flush();
        }
        expect(calls, 2);
        verifyNever(() => arbiter.command(any(), any()));
      },
    );

    test('L2 completed Grounded can switch and stays lying until L1', () async {
      final dog = buildDog();
      addTearDown(dog.dispose);
      var calls = 0;
      dog.onProfileSwitch = () async {
        calls++;
      };
      await finishL1();
      sitdownCtrl.add(true);
      await flush();
      final transitioning = Transitioning(
        const Command.sitDown(),
        const Stream<History>.empty().listen((_) {}),
        null,
      );
      when(() => arbiter.state).thenReturn(transitioning);
      switchProfileCtrl.add(null);
      await flush();
      expect(calls, 0);
      final grounded = Grounded(const Stream<History>.empty().listen((_) {}));
      when(() => arbiter.state).thenReturn(grounded);
      stateCtrl.add(grounded);
      await flush();
      clearInteractions(arbiter);
      switchProfileCtrl.add(null);
      await flush();
      expect(calls, 1);
      verifyNever(() => arbiter.command(any(), any()));
      standupCtrl.add(true);
      await flush();
      verify(
        () => arbiter.command(any(that: isA<CmdStandUp>()), any()),
      ).called(1);
    });

    test('boot H L1 R2 works without a preceding Walk', () async {
      final dog = buildDog();
      addTearDown(dog.dispose);
      var calls = 0;
      dog.onProfileSwitch = () async {
        calls++;
      };
      await finishL1();
      expect(dog.canSwitchProfile, isTrue);
      switchProfileCtrl.add(null);
      await flush();
      switchProfileCtrl.add(null);
      await flush();
      expect(calls, 2);
    });

    test(
      'release remains Walk; fresh L1 completion is required to switch back',
      () async {
        final dog = buildDog();
        addTearDown(dog.dispose);
        var calls = 0;
        dog.onProfileSwitch = () async {
          calls++;
        };
        await finishL1();
        await emitDirection(Vector3(0.5, 0, 0));
        when(() => arbiter.state).thenReturn(walking());
        await emitDirection(Vector3.zero());
        switchProfileCtrl.add(null);
        await flush();
        expect(calls, 0);
        await finishL1(enable: false);
        switchProfileCtrl.add(null);
        await flush();
        expect(calls, 1);
      },
    );

    test(
      'loading ignores joystick, L1 and duplicate R2 without queuing',
      () async {
        final dog = buildDog();
        addTearDown(dog.dispose);
        final pending = Completer<void>();
        var calls = 0;
        dog.onProfileSwitch = () {
          calls++;
          return pending.future;
        };
        await finishL1();
        switchProfileCtrl.add(null);
        await flush();
        clearInteractions(arbiter);
        await emitDirection(Vector3(1, 1, 1));
        standupCtrl.add(true);
        switchProfileCtrl.add(null);
        await flush();
        expect(calls, 1);
        verifyNever(() => arbiter.command(any(), any()));
        pending.complete();
        await flush();
        verifyNever(() => arbiter.command(any(), any()));
        await emitDirection(Vector3(0.5, 0, 0));
        verify(
          () => arbiter.command(any(that: isA<CmdWalk>()), any()),
        ).called(1);
      },
    );

    test(
      'H off or L2 during loading invalidates commit and stays available',
      () async {
        final dog = buildDog();
        addTearDown(dog.dispose);
        final pending = Completer<void>();
        dog.onProfileSwitch = () => pending.future;
        await finishL1();
        switchProfileCtrl.add(null);
        await flush();
        sitdownCtrl.add(true);
        await flush();
        expect(dog.canSwitchProfile, isFalse);
        verify(
          () => arbiter.command(any(that: isA<CmdSitDown>()), any()),
        ).called(1);
        enabledCtrl.add(false);
        await flush();
        verify(() => joint.disable()).called(1);
        pending.complete();
        await flush();
        expect(dog.canSwitchProfile, isFalse);
      },
    );

    test(
      'async load failure unlocks control and does not force sit or disable',
      () async {
        final dog = buildDog();
        addTearDown(dog.dispose);
        dog.onProfileSwitch = () async {
          throw StateError('bad model');
        };
        await finishL1();
        clearInteractions(arbiter);
        switchProfileCtrl.add(null);
        await flush();
        verifyNever(() => arbiter.fault(any()));
        verifyNever(() => joint.disable());
        verify(() => arbiter.profileSwitchInProgress = false).called(1);
        await emitDirection(Vector3(0.5, 0, 0));
        verify(
          () => arbiter.command(any(that: isA<CmdWalk>()), any()),
        ).called(1);
      },
    );

    test(
      'in-flight CMS handler prevents R2 despite stale Standing state',
      () async {
        final dog = buildDog();
        addTearDown(dog.dispose);
        var calls = 0;
        dog.onProfileSwitch = () async {
          calls++;
        };
        await finishL1();
        when(() => arbiter.isHandlingEvent).thenReturn(true);
        switchProfileCtrl.add(null);
        await flush();
        expect(calls, 0);
        when(() => arbiter.isHandlingEvent).thenReturn(false);
        await flush();
        expect(calls, 0);
      },
    );

    test('lying switch cannot commit across a new H session', () async {
      final dog = buildDog();
      addTearDown(dog.dispose);
      final s = Grounded(const Stream<History>.empty().listen((_) {}));
      when(() => arbiter.state).thenReturn(s);
      enabledCtrl.add(true);
      await flush();
      final pending = Completer<void>();
      dog.onProfileSwitch = () async {
        await pending.future;
        expect(dog.canSwitchProfile, isFalse);
      };
      switchProfileCtrl.add(null);
      await flush();
      enabledCtrl.add(false);
      await flush();
      enabledCtrl.add(true);
      await flush();
      expect(dog.canSwitchProfile, isFalse);
      pending.complete();
      await flush();
    });

    test('another switch lock cannot be stolen or cleared by R2', () async {
      final dog = buildDog();
      addTearDown(dog.dispose);
      await finishL1();
      when(() => arbiter.profileSwitchInProgress).thenReturn(true);
      switchProfileCtrl.add(null);
      await flush();
      verifyNever(() => arbiter.profileSwitchInProgress = false);
    });

    test('H off/on cannot reuse an old L1 approval', () async {
      final dog = buildDog();
      addTearDown(dog.dispose);
      await finishL1();
      enabledCtrl.add(false);
      await flush();
      enabledCtrl.add(true);
      await flush();
      expect(dog.canSwitchProfile, isFalse);
    });
  });

  group('calibrate', () {
    test('in Grounded → setZero + save', () async {
      when(
        () => arbiter.state,
      ).thenReturn(Grounded(Stream<History>.empty().listen((_) {})));

      buildDog();
      calibrateCtrl.add(null);
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.setZeroPosition()).called(1);
      verify(() => joint.setZeroSigned()).called(1);
      verify(() => joint.saveParameters()).called(1);
    });

    test('not in Grounded → ignored', () async {
      when(
        () => arbiter.state,
      ).thenReturn(Standing(Stream<History>.empty().listen((_) {})));

      buildDog();
      calibrateCtrl.add(null);
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => joint.setZeroPosition());
      verifyNever(() => joint.setZeroSigned());
      verifyNever(() => joint.saveParameters());
    });
  });

  group('error handling', () {
    test('direction stream error → arbiter.fault', () async {
      buildDog();
      directionCtrl.addError(Exception('serial disconnect'));
      await Future<void>.delayed(Duration.zero);

      verify(() => arbiter.fault(any())).called(1);
    });

    test('standup stream error → arbiter.fault', () async {
      buildDog();
      standupCtrl.addError(Exception('hardware error'));
      await Future<void>.delayed(Duration.zero);

      verify(() => arbiter.fault(any())).called(1);
    });
  });

  group('dispose', () {
    test('cancels all subscriptions', () {
      fakeAsync((async) {
        final dog = buildDog();

        // Start idle timer
        directionCtrl.add(Vector3.zero());
        async.flushMicrotasks();

        dog.dispose();

        // Timer should be cancelled — no crash after elapsed
        async.elapse(const Duration(seconds: 10));
      });
    });
  });
  group('profile command shaping', () {
    test('profile changes retain command bounds on the first input', () async {
      final captured = <A>[];
      when(() => arbiter.command(any(), any())).thenAnswer((invocation) {
        captured.add(invocation.positionalArguments.first as A);
        return true;
      });
      final dog = buildDog();

      await emitDirection(Vector3(0, 1, 0));
      expect((captured.last as CmdWalk).direction.y, closeTo(1.0, 1e-6));

      dog.switchCommandProfile(
        commandVxMax: 0.5,
        commandVyMax: 0.4,
        commandYawMax: 0.25,
        forwardMinCommand: 0.0,
        lateralMinCommand: 0.0,
        yawMinCommand: 0.0,
      );
      await emitDirection(Vector3(0, 0.55, 0));
      expect((captured.last as CmdWalk).direction.y, closeTo(0.2, 1e-7));
    });

    test(
      'release sends zero immediately without forcing wheel targets',
      () async {
        final captured = <A>[];
        when(() => arbiter.command(any(), any())).thenAnswer((invocation) {
          captured.add(invocation.positionalArguments.first as A);
          return true;
        });
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        buildDog();
        await emitDirection(Vector3(0, 1, 0));
        await emitDirection(Vector3.zero());
        expect((captured.last as CmdWalk).direction.y, 0.0);
        expect((captured.last as CmdWalk).forceWheelStop, isFalse);
      },
    );
  });

  group('live direct direction contract', () {
    late List<Vector3> sent;
    setUp(() {
      sent = [];
      when(
        () => arbiter.state,
      ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
      when(() => arbiter.command(any(), any())).thenAnswer((invocation) {
        final action = invocation.positionalArguments.first;
        if (action is CmdWalk) sent.add(Vector3.copy(action.direction));
        return true;
      });
    });

    test('three axes accelerate and reverse in one received input', () async {
      final dog = buildDog();
      dog.switchCommandProfile(
        commandVxMax: 1,
        commandVyMax: 1,
        commandYawMax: 1,
        forwardMinCommand: 0,
        lateralMinCommand: 0,
        yawMinCommand: 0,
      );
      await emitDirection(Vector3.all(1));
      expect(sent, [Vector3.all(1)]);
      await emitDirection(Vector3.all(-1));
      expect(sent, [Vector3.all(1), Vector3.all(-1)]);
      await emitDirection(Vector3.zero());
      expect(sent.last, Vector3.zero());
      dog.dispose();
    });

    test('minus 0.855 release has no deceleration tail', () async {
      final dog = buildDog();
      dog.switchCommandProfile(
        commandVxMax: 1,
        commandVyMax: 1,
        commandYawMax: 1,
        forwardMinCommand: 0,
        lateralMinCommand: 0,
        yawMinCommand: 0,
      );
      await emitDirection(Vector3(-0.8695, 0, 0));
      expect(sent.last.x, closeTo(-0.855, 1e-6));
      await emitDirection(Vector3.zero());
      expect(sent.last.x, 0);
      expect(sent.length, 2);
      dog.dispose();
    });

    test(
      'received targets remain direct across clock gaps and state changes',
      () async {
        final dog = buildDog();
        await emitDirection(Vector3(1, 0, 0));
        expect(sent.last.x, 1.5);
        commandTime = commandTime.add(const Duration(seconds: 1));
        await emitDirection(Vector3(-1, 0, 0));
        expect(sent.last.x, -1.5);
        stateCtrl.add(Grounded(Stream<History>.empty().listen((_) {})));
        await Future<void>.delayed(Duration.zero);
        await emitDirection(Vector3(1, 0, 0));
        expect(sent.last.x, 1.5);
        dog.dispose();
      },
    );

    test(
      'H disable stops immediately and disabled inputs cannot accumulate',
      () async {
        final dog = buildDog();
        await emitDirection(Vector3(1, 0, 0));
        enabledCtrl.add(false);
        await Future<void>.delayed(Duration.zero);
        verify(() => joint.disable()).called(1);
        expect(sent.last, Vector3.zero());
        final count = sent.length;
        await emitDirection(Vector3(1, 0, 0), 3);
        expect(sent.length, count);
        enabledCtrl.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(sent.length, count);
        await emitDirection(Vector3(1, 0, 0));
        expect(sent.last.x, 1.5);
        dog.dispose();
      },
    );

    test('L1 still requires physical settle after immediate command zero', () {
      fakeAsync((async) {
        final dog = buildDog();
        enabledCtrl.add(true);
        async.flushMicrotasks();
        directionCtrl.add(Vector3(0, 1, 0));
        async.flushMicrotasks();
        directionCtrl.add(Vector3.zero());
        async.flushMicrotasks();
        expect(sent.last, Vector3.zero());
        standupCtrl.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 250));
        verifyNever(() => arbiter.command(any(that: isA<CmdStandUp>()), any()));
        async.elapse(const Duration(milliseconds: 50));
        verify(
          () => arbiter.command(any(that: isA<CmdStandUp>()), any()),
        ).called(1);
        dog.dispose();
      });
    });
  });
}
