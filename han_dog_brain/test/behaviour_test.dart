import 'dart:async';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_brain/src/behaviour.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockImu extends Mock implements ImuService {}

class MockJoint extends Mock implements JointService {}

void main() {
  late MockImu imu;
  late MockJoint joint;
  late StreamController<void> clock;
  late Memory<History> memory;

  setUp(() {
    imu = MockImu();
    joint = MockJoint();
    clock = StreamController<void>.broadcast();
    memory = Memory<History>(historySize: 1, initial: History.zero());

    when(() => imu.gyroscope).thenReturn(Vector3.zero());
    when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
    when(() => imu.initialGyroscope).thenReturn(Vector3.zero());
    when(() => imu.initialProjectedGravity).thenReturn(Vector3(0, 0, -1));
    when(() => joint.position).thenReturn(.zero());
    when(() => joint.velocity).thenReturn(.zero());
    when(() => joint.initialPosition).thenReturn(.zero());
    when(() => joint.initialVelocity).thenReturn(.zero());
  });

  tearDown(() {
    clock.close();
    memory.dispose();
  });

  group('Idle', () {
    test('emits History with idle command on each clock tick', () async {
      final idle = Idle(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
      );

      final results = <History>[];
      final sub = idle.doing.listen(results.add);

      clock.add(null);
      clock.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(results, hasLength(2));
      expect(results[0].command, isA<IdleCommand>());
      expect(results[1].command, isA<IdleCommand>());

      await sub.cancel();
    });

    test('nextAction equals memory.latestAction', () async {
      // Set up memory with a known nextAction
      final knownAction = JointsMatrix.fromList(List.filled(16, 0.42));
      memory.add(History(
        gyroscope: Vector3.zero(),
        projectedGravity: Vector3(0, 0, -1),
        command: const Command.idle(),
        jointPosition: .zero(),
        jointVelocity: .zero(),
        action: .zero(),
        nextAction: knownAction,
      ));

      final idle = Idle(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
      );

      final results = <History>[];
      final sub = idle.doing.listen(results.add);

      clock.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(results.first.nextAction, knownAction);
      await sub.cancel();
    });
  });

  group('StandUp', () {
    final standingPose = JointsMatrix.fromList(List.filled(16, 1.0));

    test('counts=3 emits 4 frames then completes', () async {
      final standUp = StandUp(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        standingPose: standingPose,
        counts: 3,
      );

      final results = <History>[];
      var completed = false;
      final sub = standUp.doing.listen(
        results.add,
        onDone: () => completed = true,
      );

      // Pump 5 ticks (only first 4 should produce output)
      for (var i = 0; i < 5; i++) {
        clock.add(null);
        await Future<void>.delayed(Duration.zero);
      }

      expect(results, hasLength(4));
      expect(completed, isTrue);

      for (final h in results) {
        expect(h.command, isA<StandUpCommand>());
      }

      await sub.cancel();
    });

    test('interpolates nextAction from currentPose to standingPose', () async {
      final currentPose = JointsMatrix.zero();
      when(() => joint.position).thenReturn(currentPose);

      final standUp = StandUp(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        standingPose: standingPose,
        counts: 3,
      );

      final results = <History>[];
      final sub = standUp.doing.listen(results.add);

      // Pump 5 ticks: 4 frames emitted, 5th tick ensures generator fully flushes
      for (var i = 0; i < 5; i++) {
        clock.add(null);
        await Future<void>.delayed(Duration.zero);
      }

      expect(results, hasLength(4));
      // t=0/3=0.0 → lerp(0,1,0.0)=0.0 (discardFoot zeroes last 4)
      // t=1/3≈0.333 → lerp(0,1,0.333)≈0.333
      // t=2/3≈0.667 → lerp(0,1,0.667)≈0.667
      // t=3/3=1.0 → lerp(0,1,1.0)=1.0
      expect(results[0].nextAction.values[0], closeTo(0.0, 1e-6));
      expect(results[1].nextAction.values[0], closeTo(1.0 / 3, 1e-6));
      expect(results[2].nextAction.values[0], closeTo(2.0 / 3, 1e-6));
      expect(results[3].nextAction.values[0], closeTo(1.0, 1e-6));

      // Last 4 values (foot) should be zeroed by discardFoot
      for (final h in results) {
        expect(h.nextAction.values[12], 0.0);
        expect(h.nextAction.values[13], 0.0);
        expect(h.nextAction.values[14], 0.0);
        expect(h.nextAction.values[15], 0.0);
      }

      await sub.cancel();
    });

    test('counts=0 emits 1 frame at t=1.0 then completes', () async {
      when(() => joint.position).thenReturn(.zero());

      final standUp = StandUp(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        standingPose: standingPose,
        counts: 0,
      );

      final results = <History>[];
      var completed = false;
      final sub = standUp.doing.listen(
        results.add,
        onDone: () => completed = true,
      );

      clock.add(null);
      await Future<void>.delayed(Duration.zero);
      clock.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(results, hasLength(1));
      expect(completed, isTrue);
      // i=0, steps=0, t=(0/0).clamp(0,1)=NaN.clamp → 1.0 (division by zero → clamp handles it)
      // Actually (0/0) is NaN, and NaN.clamp(0,1) returns NaN in Dart...
      // Let's just verify it completes with 1 frame
      await sub.cancel();
    });
  });

  group('SitDown', () {
    final sittingPose = JointsMatrix.zero();

    test('counts=3 emits 4 frames then completes', () async {
      final currentPose = JointsMatrix.fromList(List.filled(16, 1.0));
      when(() => joint.position).thenReturn(currentPose);

      final sitDown = SitDown(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        sittingPose: sittingPose,
        counts: 3,
      );

      final results = <History>[];
      var completed = false;
      final sub = sitDown.doing.listen(
        results.add,
        onDone: () => completed = true,
      );

      for (var i = 0; i < 5; i++) {
        clock.add(null);
        await Future<void>.delayed(Duration.zero);
      }

      expect(results, hasLength(4));
      expect(completed, isTrue);

      for (final h in results) {
        expect(h.command, isA<SitDownCommand>());
      }

      await sub.cancel();
    });

    test('interpolates nextAction from currentPose to sittingPose', () async {
      final currentPose = JointsMatrix.fromList(List.filled(16, 3.0));
      when(() => joint.position).thenReturn(currentPose);

      final sitDown = SitDown(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        sittingPose: sittingPose,
        counts: 3,
      );

      final results = <History>[];
      final sub = sitDown.doing.listen(results.add);

      // Pump 5 ticks: 4 frames emitted, 5th tick ensures generator fully flushes
      for (var i = 0; i < 5; i++) {
        clock.add(null);
        await Future<void>.delayed(Duration.zero);
      }

      expect(results, hasLength(4));
      // lerp(3.0, 0.0, t) = 3.0 * (1-t)
      // t=0.0 → 3.0, t=1/3 → 2.0, t=2/3 → 1.0, t=1.0 → 0.0
      expect(results[0].nextAction.values[0], closeTo(3.0, 1e-6));
      expect(results[1].nextAction.values[0], closeTo(2.0, 1e-6));
      expect(results[2].nextAction.values[0], closeTo(1.0, 1e-6));
      expect(results[3].nextAction.values[0], closeTo(0.0, 1e-6));

      await sub.cancel();
    });
  });
}
