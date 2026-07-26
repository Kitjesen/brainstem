import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockBrain extends Mock implements Brain {}

class MockArbiter extends Mock implements ControlArbiter {}

class MockRealImu extends Mock implements RealImu {}

class MockRealJoint extends Mock implements RealJoint {}

class MockRealController extends Mock implements RealController {}

void main() {
  late MockBrain brain;
  late MockArbiter arbiter;
  late MockRealImu imu;
  late MockRealJoint joint;
  late MockRealController controller;

  // StreamControllers for each controller stream
  late StreamController<Vector3> directionCtrl;
  late StreamController<bool> standupCtrl;
  late StreamController<bool> sitdownCtrl;
  late StreamController<bool> idleCtrl;
  late StreamController<bool> redCtrl;
  late StreamController<bool> enabledCtrl;
  late StreamController<void> calibrateCtrl;
  late StreamController<void> switchProfileCtrl;
  late StreamController<double> bodyHeightCtrl;
  late StreamController<S> stateCtrl;

  final inferKp = JointsMatrix.fromList(List.filled(16, 1.0));
  final inferKd = JointsMatrix.fromList(List.filled(16, 2.0));
  final standUpKp = JointsMatrix.fromList(List.filled(16, 3.0));
  final standUpKd = JointsMatrix.fromList(List.filled(16, 4.0));
  final sitDownKp = JointsMatrix.fromList(List.filled(16, 5.0));
  final sitDownKd = JointsMatrix.fromList(List.filled(16, 6.0));

  RobotProfile profile({
    String observationType = 'standard',
    double bodyHeightCommand = 0.40,
    double minBodyHeightCommand = 0.20,
    double maxBodyHeightCommand = 0.54,
  }) => RobotProfile(
    name: observationType,
    modelPath: 'model/$observationType.onnx',
    standingPose: JointsMatrix.zero(),
    sittingPose: JointsMatrix.zero(),
    inferKp: inferKp,
    inferKd: inferKd,
    standUpKp: standUpKp,
    standUpKd: standUpKd,
    sitDownKp: sitDownKp,
    sitDownKd: sitDownKd,
    observationType: observationType,
    bodyHeightCommand: bodyHeightCommand,
    minBodyHeightCommand: minBodyHeightCommand,
    maxBodyHeightCommand: maxBodyHeightCommand,
  );

  setUpAll(() {
    registerFallbackValue(const A.init());
    registerFallbackValue(ControlSource.yunzhuo);
    registerFallbackValue(Vector3.zero());
    registerFallbackValue(JointsMatrix.zero());
  });

  RealControlDog buildDog({
    (double, double, double) velocityCommandMin = (-3.0, -3.0, -3.0),
    (double, double, double) velocityCommandMax = (3.0, 3.0, 3.0),
    RobotProfile? initialProfile,
  }) {
    return RealControlDog(
      brain: brain,
      arbiter: arbiter,
      imu: imu,
      joint: joint,
      controller: controller,
      inferKp: inferKp,
      inferKd: inferKd,
      standUpKp: standUpKp,
      standUpKd: standUpKd,
      sitDownKp: sitDownKp,
      sitDownKd: sitDownKd,
      velocityCommandMin: velocityCommandMin,
      velocityCommandMax: velocityCommandMax,
      initialProfile: initialProfile,
    );
  }

  setUp(() {
    brain = MockBrain();
    arbiter = MockArbiter();
    imu = MockRealImu();
    joint = MockRealJoint();
    controller = MockRealController();

    directionCtrl = StreamController<Vector3>.broadcast();
    standupCtrl = StreamController<bool>.broadcast();
    sitdownCtrl = StreamController<bool>.broadcast();
    idleCtrl = StreamController<bool>.broadcast();
    redCtrl = StreamController<bool>.broadcast();
    enabledCtrl = StreamController<bool>.broadcast();
    calibrateCtrl = StreamController<void>.broadcast();
    switchProfileCtrl = StreamController<void>.broadcast();
    bodyHeightCtrl = StreamController<double>.broadcast();
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

    when(() => arbiter.stateStream).thenAnswer((_) => stateCtrl.stream);
    when(() => arbiter.state).thenReturn(const Zero());
    when(() => arbiter.command(any(), any())).thenReturn(true);
    when(() => arbiter.fault(any())).thenReturn(null);
    when(() => brain.bodyHeightCommand).thenReturn(0.40);
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
    bodyHeightCtrl.close();
    stateCtrl.close();
  });

  group('body-height profile', () {
    test('standard profile never accesses bodyHeightAxis', () {
      final dog = buildDog(initialProfile: profile());

      verifyNever(() => controller.bodyHeightAxis);
      dog.dispose();
    });

    test('subscribes to bodyHeightAxis only for bodyHeight profile', () {
      when(
        () => controller.bodyHeightAxis,
      ).thenAnswer((_) => bodyHeightCtrl.stream);

      final dog = buildDog(
        initialProfile: profile(observationType: 'bodyHeight'),
      );

      verify(() => controller.bodyHeightAxis).called(1);
      dog.dispose();
    });

    test('requires a BodyHeightAxisInput controller', () {
      final standardController = _StandardGamepad();

      expect(
        () => RealControlDog(
          brain: brain,
          arbiter: arbiter,
          imu: imu,
          joint: joint,
          controller: standardController,
          inferKp: inferKp,
          inferKd: inferKd,
          standUpKp: standUpKp,
          standUpKd: standUpKd,
          sitDownKp: sitDownKp,
          sitDownKd: sitDownKd,
          initialProfile: profile(observationType: 'bodyHeight'),
        ),
        throwsArgumentError,
      );
      standardController.dispose();
    });

    test('full-scale input adds exactly 0.0004m every 20ms', () {
      fakeAsync((async) {
        when(
          () => controller.bodyHeightAxis,
        ).thenAnswer((_) => bodyHeightCtrl.stream);
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog(
          initialProfile: profile(observationType: 'bodyHeight'),
        );

        bodyHeightCtrl.add(1.0);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));

        final command =
            verify(
                  () => arbiter.command(
                    captureAny(that: isA<CmdSetBodyHeight>()),
                    ControlSource.yunzhuo,
                  ),
                ).captured.single
                as CmdSetBodyHeight;
        expect(command.meters, closeTo(0.4004, 1e-12));
        dog.dispose();
      });
    });

    test('first active input resumes from the applied brain height', () {
      fakeAsync((async) {
        when(
          () => controller.bodyHeightAxis,
        ).thenAnswer((_) => bodyHeightCtrl.stream);
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        when(() => brain.bodyHeightCommand).thenReturn(0.50);
        final dog = buildDog(
          initialProfile: profile(observationType: 'bodyHeight'),
        );

        bodyHeightCtrl.add(1.0);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));

        final command =
            verify(
                  () => arbiter.command(
                    captureAny(that: isA<CmdSetBodyHeight>()),
                    ControlSource.yunzhuo,
                  ),
                ).captured.single
                as CmdSetBodyHeight;
        expect(command.meters, closeTo(0.5004, 1e-12));
        dog.dispose();
      });
    });

    test('axis returning to zero resynchronizes on the next activation', () {
      fakeAsync((async) {
        when(
          () => controller.bodyHeightAxis,
        ).thenAnswer((_) => bodyHeightCtrl.stream);
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        when(() => brain.bodyHeightCommand).thenReturn(0.45);
        final dog = buildDog(
          initialProfile: profile(observationType: 'bodyHeight'),
        );

        bodyHeightCtrl.add(1.0);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        bodyHeightCtrl.add(0.0);
        async.flushMicrotasks();
        when(() => brain.bodyHeightCommand).thenReturn(0.50);
        bodyHeightCtrl.add(1.0);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));

        final commands = verify(
          () => arbiter.command(
            captureAny(that: isA<CmdSetBodyHeight>()),
            ControlSource.yunzhuo,
          ),
        ).captured.cast<CmdSetBodyHeight>();
        expect(commands.last.meters, closeTo(0.5004, 1e-12));
        dog.dispose();
      });
    });

    test('non-zero axis while Standing first sends walk zero', () async {
      when(
        () => controller.bodyHeightAxis,
      ).thenAnswer((_) => bodyHeightCtrl.stream);
      when(
        () => arbiter.state,
      ).thenReturn(Standing(Stream<History>.empty().listen((_) {})));
      final dog = buildDog(
        initialProfile: profile(observationType: 'bodyHeight'),
      );

      bodyHeightCtrl.add(1.0);
      await Future<void>.delayed(Duration.zero);

      final command =
          verify(
                () => arbiter.command(
                  captureAny(that: isA<CmdWalk>()),
                  ControlSource.yunzhuo,
                ),
              ).captured.single
              as CmdWalk;
      expect(command.direction, Vector3.zero());
      dog.dispose();
    });

    test('R1 while Standing resets height to profile default', () async {
      when(
        () => controller.bodyHeightAxis,
      ).thenAnswer((_) => bodyHeightCtrl.stream);
      when(
        () => arbiter.state,
      ).thenReturn(Standing(Stream<History>.empty().listen((_) {})));
      final dog = buildDog(
        initialProfile: profile(observationType: 'bodyHeight'),
      );

      idleCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      final command =
          verify(
                () => arbiter.command(
                  captureAny(that: isA<CmdSetBodyHeight>()),
                  ControlSource.yunzhuo,
                ),
              ).captured.single
              as CmdSetBodyHeight;
      expect(command.meters, 0.40);
      verifyNever(
        () => arbiter.command(
          any(that: isA<CmdStandUp>()),
          ControlSource.yunzhuo,
        ),
      );
      dog.dispose();
    });

    test('R1 while Walking keeps the standUp behavior', () async {
      when(
        () => controller.bodyHeightAxis,
      ).thenAnswer((_) => bodyHeightCtrl.stream);
      when(
        () => arbiter.state,
      ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
      final dog = buildDog(
        initialProfile: profile(observationType: 'bodyHeight'),
      );

      idleCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(that: isA<CmdStandUp>()),
          ControlSource.yunzhuo,
        ),
      ).called(1);
      verifyNever(
        () => arbiter.command(
          any(that: isA<CmdSetBodyHeight>()),
          ControlSource.yunzhuo,
        ),
      );
      dog.dispose();
    });

    test(
      'rejected Standing R1 reset preserves the active axis and baseline',
      () {
        fakeAsync((async) {
          when(
            () => controller.bodyHeightAxis,
          ).thenAnswer((_) => bodyHeightCtrl.stream);
          when(
            () => arbiter.state,
          ).thenReturn(Standing(Stream<History>.empty().listen((_) {})));
          when(() => brain.bodyHeightCommand).thenReturn(0.50);
          when(() => arbiter.command(any(), any())).thenReturn(false);
          final dog = buildDog(
            initialProfile: profile(observationType: 'bodyHeight'),
          );

          bodyHeightCtrl.add(1.0);
          async.flushMicrotasks();
          idleCtrl.add(true);
          async.flushMicrotasks();

          final reset =
              verify(
                    () => arbiter.command(
                      captureAny(that: isA<CmdSetBodyHeight>()),
                      ControlSource.yunzhuo,
                    ),
                  ).captured.single
                  as CmdSetBodyHeight;
          expect(reset.meters, 0.40);

          clearInteractions(arbiter);
          when(
            () => arbiter.state,
          ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
          when(() => arbiter.command(any(), any())).thenReturn(true);
          async.elapse(const Duration(milliseconds: 20));

          final resumed =
              verify(
                    () => arbiter.command(
                      captureAny(that: isA<CmdSetBodyHeight>()),
                      ControlSource.yunzhuo,
                    ),
                  ).captured.single
                  as CmdSetBodyHeight;
          expect(resumed.meters, closeTo(0.5004, 1e-12));
          dog.dispose();
        });
      },
    );

    test('Transitioning does not integrate body height', () {
      fakeAsync((async) {
        when(
          () => controller.bodyHeightAxis,
        ).thenAnswer((_) => bodyHeightCtrl.stream);
        when(() => arbiter.state).thenReturn(
          Transitioning(
            const Command.standUp(),
            Stream<History>.empty().listen((_) {}),
            null,
          ),
        );
        final dog = buildDog(
          initialProfile: profile(observationType: 'bodyHeight'),
        );

        bodyHeightCtrl.add(1.0);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));

        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdSetBodyHeight>()),
            ControlSource.yunzhuo,
          ),
        );
        dog.dispose();
      });
    });

    test('rejects invalid body-height profile bounds', () {
      when(
        () => controller.bodyHeightAxis,
      ).thenAnswer((_) => bodyHeightCtrl.stream);
      final invalidProfiles = [
        profile(observationType: 'bodyHeight', bodyHeightCommand: double.nan),
        profile(
          observationType: 'bodyHeight',
          minBodyHeightCommand: double.negativeInfinity,
        ),
        profile(
          observationType: 'bodyHeight',
          maxBodyHeightCommand: double.infinity,
        ),
        profile(
          observationType: 'bodyHeight',
          minBodyHeightCommand: 0.50,
          maxBodyHeightCommand: 0.40,
        ),
        profile(observationType: 'bodyHeight', bodyHeightCommand: 0.55),
      ];

      for (final invalidProfile in invalidProfiles) {
        expect(
          () => buildDog(initialProfile: invalidProfile),
          throwsArgumentError,
        );
      }
    });

    test('deadzone ignores 0.099 but exactly 0.10 remains active', () {
      fakeAsync((async) {
        when(
          () => controller.bodyHeightAxis,
        ).thenAnswer((_) => bodyHeightCtrl.stream);
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog(
          initialProfile: profile(observationType: 'bodyHeight'),
        );

        bodyHeightCtrl.add(0.099);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdSetBodyHeight>()),
            ControlSource.yunzhuo,
          ),
        );

        bodyHeightCtrl.add(0.10);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        final command =
            verify(
                  () => arbiter.command(
                    captureAny(that: isA<CmdSetBodyHeight>()),
                    ControlSource.yunzhuo,
                  ),
                ).captured.single
                as CmdSetBodyHeight;
        expect(command.meters, 0.40004);
        dog.dispose();
      });
    });

    test('integrated height clamps to the profile min and max', () {
      fakeAsync((async) {
        when(
          () => controller.bodyHeightAxis,
        ).thenAnswer((_) => bodyHeightCtrl.stream);
        when(
          () => arbiter.state,
        ).thenReturn(Walking(Stream<History>.empty().listen((_) {})));
        final dog = buildDog(
          initialProfile: profile(
            observationType: 'bodyHeight',
            bodyHeightCommand: 0.4001,
            minBodyHeightCommand: 0.4000,
            maxBodyHeightCommand: 0.4002,
          ),
        );

        bodyHeightCtrl.add(1.0);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        bodyHeightCtrl.add(-1.0);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));

        final commands = verify(
          () => arbiter.command(
            captureAny(that: isA<CmdSetBodyHeight>()),
            ControlSource.yunzhuo,
          ),
        ).captured.cast<CmdSetBodyHeight>();
        expect(commands.map((command) => command.meters), [0.4002, 0.4000]);
        dog.dispose();
      });
    });

    test('dispose cancels body-height axis integration', () {
      fakeAsync((async) {
        when(
          () => controller.bodyHeightAxis,
        ).thenAnswer((_) => bodyHeightCtrl.stream);
        final dog = buildDog(
          initialProfile: profile(observationType: 'bodyHeight'),
        );

        bodyHeightCtrl.add(1.0);
        async.flushMicrotasks();
        dog.dispose();
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 1));

        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdSetBodyHeight>()),
            ControlSource.yunzhuo,
          ),
        );
      });
    });

    test('R2 does not trigger profile switching', () async {
      when(
        () => controller.bodyHeightAxis,
      ).thenAnswer((_) => bodyHeightCtrl.stream);
      when(
        () => arbiter.state,
      ).thenReturn(Standing(Stream<History>.empty().listen((_) {})));
      final dog = buildDog(
        initialProfile: profile(observationType: 'bodyHeight'),
      );
      var switchCount = 0;
      dog.onProfileSwitch = () => switchCount++;

      switchProfileCtrl.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(switchCount, 0);
      dog.dispose();
    });
  });

  group('kp/kd switching', () {
    test('Walking → inferKp/inferKd', () async {
      buildDog();
      stateCtrl.add(Walking(Stream<History>.empty().listen((_) {})));
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.kpExt = inferKp).called(1);
      verify(() => joint.kdExt = inferKd).called(1);
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
      directionCtrl.add(Vector3(1, 0, 0));
      await Future<void>.delayed(Duration.zero);

      verify(
        () => arbiter.command(any(that: isA<CmdWalk>()), ControlSource.yunzhuo),
      ).called(1);
    });

    test('profile bounds clamp every controller velocity axis', () async {
      buildDog(
        velocityCommandMin: (-2.5, -1.0, -1.0),
        velocityCommandMax: (2.5, 1.0, 1.0),
      );
      directionCtrl.add(Vector3(1.5, 1.5, -1.5));
      await Future<void>.delayed(Duration.zero);

      final command =
          verify(
                () => arbiter.command(
                  captureAny(that: isA<CmdWalk>()),
                  ControlSource.yunzhuo,
                ),
              ).captured.single
              as CmdWalk;
      expect(command.direction.x, 1.5);
      expect(command.direction.y, 1.0);
      expect(command.direction.z, -1.0);
    });

    test('non-finite controller direction is ignored', () async {
      buildDog();
      directionCtrl.add(Vector3(double.nan, 0, 0));
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => arbiter.command(any(), ControlSource.yunzhuo));
    });
  });
  group('buttons', () {
    test('L1 → standUp', () async {
      buildDog();
      standupCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(that: isA<CmdStandUp>()),
          ControlSource.yunzhuo,
        ),
      ).called(1);
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

    test('red → joint.disable(clearErrors: true)', () async {
      buildDog();
      redCtrl.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(() => joint.disable(clearErrors: true)).called(1);
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
}

class _StandardGamepad implements Gamepad {
  final _direction = StreamController<Vector3>.broadcast();
  final _bools = StreamController<bool>.broadcast();
  final _voids = StreamController<void>.broadcast();

  @override
  Stream<void> get calibrate => _voids.stream;

  @override
  Stream<Vector3> get direction => _direction.stream;

  @override
  Stream<bool> get enabled => _bools.stream;

  @override
  Stream<bool> get idle => _bools.stream;

  @override
  Stream<bool> get red => _bools.stream;

  @override
  Stream<bool> get sitdown => _bools.stream;

  @override
  Stream<bool> get standup => _bools.stream;

  @override
  Stream<void> get switchProfile => _voids.stream;

  @override
  void dispose() {
    _direction.close();
    _bools.close();
    _voids.close();
  }
}
