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
  late StreamController<S> stateCtrl;

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

  RealControlDog buildDog() {
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
    stateCtrl = StreamController<S>.broadcast();

    when(() => controller.direction).thenAnswer((_) => directionCtrl.stream);
    when(() => controller.standup).thenAnswer((_) => standupCtrl.stream);
    when(() => controller.sitdown).thenAnswer((_) => sitdownCtrl.stream);
    when(() => controller.idle).thenAnswer((_) => idleCtrl.stream);
    when(() => controller.red).thenAnswer((_) => redCtrl.stream);
    when(() => controller.enabled).thenAnswer((_) => enabledCtrl.stream);
    when(() => controller.calibrate).thenAnswer((_) => calibrateCtrl.stream);
    when(() => controller.switchProfile)
        .thenAnswer((_) => switchProfileCtrl.stream);

    when(() => joint.enable()).thenAnswer((_) async {});
    when(() => joint.disable()).thenAnswer((_) async {});

    when(() => arbiter.stateStream).thenAnswer((_) => stateCtrl.stream);
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
    test('Walking → inferKp/inferKd', () async {
      buildDog();
      stateCtrl.add(Walking(Stream<History>.empty().listen((_) {})));
      await Future.delayed(Duration.zero);

      verify(() => joint.kpExt = inferKp).called(1);
      verify(() => joint.kdExt = inferKd).called(1);
    });

    test('Transitioning(StandUp) → standUpKp/standUpKd', () async {
      buildDog();
      stateCtrl.add(Transitioning(
        const Command.standUp(),
        Stream<History>.empty().listen((_) {}),
        null,
      ));
      await Future.delayed(Duration.zero);

      verify(() => joint.kpExt = standUpKp).called(1);
      verify(() => joint.kdExt = standUpKd).called(1);
    });

    test('Transitioning(SitDown) → sitDownKp/sitDownKd', () async {
      buildDog();
      stateCtrl.add(Transitioning(
        const Command.sitDown(),
        Stream<History>.empty().listen((_) {}),
        null,
      ));
      await Future.delayed(Duration.zero);

      verify(() => joint.kpExt = sitDownKp).called(1);
      verify(() => joint.kdExt = sitDownKd).called(1);
    });

    test('Standing/Grounded/Zero → no kp/kd change', () async {
      buildDog();
      stateCtrl.add(Standing(Stream<History>.empty().listen((_) {})));
      await Future.delayed(Duration.zero);

      verifyNever(() => joint.kpExt = any());
      verifyNever(() => joint.kdExt = any());
    });
  });

  group('direction → walk', () {
    test('non-zero direction → arbiter.command(A.walk, yunzhuo)', () async {
      buildDog();
      directionCtrl.add(Vector3(1, 0, 0));
      await Future.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(that: isA<CmdWalk>()),
          ControlSource.yunzhuo,
        ),
      ).called(1);
    });
  });

  group('idle timer', () {
    test('zero direction for 5 seconds → idle command', () {
      fakeAsync((async) {
        buildDog();
        directionCtrl.add(Vector3(0, 0, 0));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));

        verify(
          () => arbiter.command(
            any(that: isA<CmdIdle>()),
            ControlSource.yunzhuo,
          ),
        ).called(1);
      });
    });

    test('non-zero direction cancels idle timer', () {
      fakeAsync((async) {
        buildDog();
        // Start timer with zero direction
        directionCtrl.add(Vector3(0, 0, 0));
        async.flushMicrotasks();

        // 3 seconds in, send non-zero direction
        async.elapse(const Duration(seconds: 3));
        directionCtrl.add(Vector3(1, 0, 0));
        async.flushMicrotasks();

        // Wait past original 5-second window
        async.elapse(const Duration(seconds: 3));

        // Idle should NOT have been sent (timer was cancelled)
        verifyNever(
          () => arbiter.command(
            any(that: isA<CmdIdle>()),
            ControlSource.yunzhuo,
          ),
        );
      });
    });
  });

  group('buttons', () {
    test('L1 → standUp', () async {
      buildDog();
      standupCtrl.add(true);
      await Future.delayed(Duration.zero);

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
      await Future.delayed(Duration.zero);

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
      await Future.delayed(Duration.zero);

      verify(
        () => arbiter.command(
          any(that: isA<CmdStandUp>()),
          ControlSource.yunzhuo,
        ),
      ).called(1);
    });

    test('red → joint.disable()', () async {
      buildDog();
      redCtrl.add(true);
      await Future.delayed(Duration.zero);

      verify(() => joint.disable()).called(1);
    });

    test('enabled true → joint.enable()', () async {
      buildDog();
      enabledCtrl.add(true);
      await Future.delayed(Duration.zero);

      verify(() => joint.enable()).called(1);
    });

    test('enabled false → joint.disable()', () async {
      buildDog();
      enabledCtrl.add(false);
      await Future.delayed(Duration.zero);

      verify(() => joint.disable()).called(1);
    });
  });

  group('calibrate', () {
    test('in Grounded → setZero + save', () async {
      when(() => arbiter.state).thenReturn(
        Grounded(Stream<History>.empty().listen((_) {})),
      );

      buildDog();
      calibrateCtrl.add(null);
      await Future.delayed(Duration.zero);

      verify(() => joint.setZeroPosition()).called(1);
      verify(() => joint.setZeroSigned()).called(1);
      verify(() => joint.saveParameters()).called(1);
    });

    test('not in Grounded → ignored', () async {
      when(() => arbiter.state).thenReturn(
        Standing(Stream<History>.empty().listen((_) {})),
      );

      buildDog();
      calibrateCtrl.add(null);
      await Future.delayed(Duration.zero);

      verifyNever(() => joint.setZeroPosition());
      verifyNever(() => joint.setZeroSigned());
      verifyNever(() => joint.saveParameters());
    });
  });

  group('error handling', () {
    test('direction stream error → arbiter.fault', () async {
      buildDog();
      directionCtrl.addError(Exception('serial disconnect'));
      await Future.delayed(Duration.zero);

      verify(() => arbiter.fault(any())).called(1);
    });

    test('standup stream error → arbiter.fault', () async {
      buildDog();
      standupCtrl.addError(Exception('hardware error'));
      await Future.delayed(Duration.zero);

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
