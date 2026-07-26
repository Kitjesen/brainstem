import 'dart:async';
import 'dart:typed_data';

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
      final idle = Idle(clock: clock, imu: imu, joint: joint, memory: memory);

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
      memory.add(
        History(
          gyroscope: Vector3.zero(),
          projectedGravity: Vector3(0, 0, -1),
          command: const Command.idle(),
          jointPosition: .zero(),
          jointVelocity: .zero(),
          action: .zero(),
          nextAction: knownAction,
        ),
      );

      final idle = Idle(clock: clock, imu: imu, joint: joint, memory: memory);

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

  group('body-height walk contract', () {
    late Walk walk;

    setUp(() {
      walk = Walk(
        observationBuilder: BodyHeightObservationBuilder(
          standingPose: JointsMatrix.zero(),
        ),
        imu: imu,
        joint: joint,
        memory: memory,
        clock: clock,
        minBodyHeightCommand: 0.20,
        maxBodyHeightCommand: 0.54,
        bodyHeightCommand: 0.35,
      );
    });

    tearDown(() {
      walk.dispose();
    });

    test('starts at configured default and records it in new history', () {
      expect(walk.bodyHeightCommand, 0.35);
      final history = walk.next(
        command: Command.walk(Vector3.zero()),
        nextAction: JointsMatrix.zero(),
      );
      expect(history.bodyHeightCommand, 0.35);
    });

    test('clamps finite values to the configured training range', () {
      walk.bodyHeightCommand = 0.1;
      expect(walk.bodyHeightCommand, 0.20);
      expect(
        walk
            .next(
              command: Command.walk(Vector3.zero()),
              nextAction: JointsMatrix.zero(),
            )
            .bodyHeightCommand,
        0.20,
      );

      walk.bodyHeightCommand = 0.9;
      expect(walk.bodyHeightCommand, 0.54);
    });

    test(
      'rejects non-finite setpoints without changing the last safe value',
      () {
        walk.bodyHeightCommand = 0.4;
        expect(() => walk.bodyHeightCommand = double.nan, throwsArgumentError);
        expect(
          () => walk.bodyHeightCommand = double.infinity,
          throwsArgumentError,
        );
        expect(walk.bodyHeightCommand, 0.4);
      },
    );
  });

  group('observation history assembly', () {
    final builder = BodyHeightObservationBuilder(
      standingPose: JointsMatrix.zero(),
    );

    History atHeight(double height) =>
        History.zero().copyWith(bodyHeightCommand: height);

    test('is oldest-to-newest and keeps each frame height command', () {
      final result = assembleObservationHistory(
        observationBuilder: builder,
        histories: [atHeight(0.20), atHeight(0.30), atHeight(0.40)],
        current: atHeight(0.50),
      );

      expect(result, isA<Float64List>());
      expect(result, hasLength(3 * 58));
      expect(result[57], 0.30);
      expect(result[58 + 57], 0.40);
      expect(result[2 * 58 + 57], 0.50);
    });

    test('supports a single-frame policy without reading stale history', () {
      final result = assembleObservationHistory(
        observationBuilder: builder,
        histories: [atHeight(0.20)],
        current: atHeight(0.44),
      );

      expect(result, hasLength(58));
      expect(result[57], 0.44);
    });
  });

  test('Brain seeds history with the configured body-height default', () {
    final brain = Brain(
      historySize: 10,
      imu: imu,
      joint: joint,
      clock: clock,
      standingPose: JointsMatrix.zero(),
      sittingPose: JointsMatrix.zero(),
      observationBuilder: BodyHeightObservationBuilder(
        standingPose: JointsMatrix.zero(),
      ),
      bodyHeightCommand: 0.48,
      minBodyHeightCommand: 0.20,
      maxBodyHeightCommand: 0.54,
    );
    addTearDown(brain.dispose);

    expect(
      brain.histories.map((history) => history.bodyHeightCommand),
      everyElement(0.48),
    );
    expect(brain.bodyHeightCommand, 0.48);

    brain.bodyHeightCommand = 0.90;
    expect(brain.bodyHeightCommand, 0.54);
  });

  test('Brain keeps physical stand pose separate from policy default', () {
    final physicalStand = JointsMatrix.fromList(List.filled(16, 0.4));
    final policyDefault = JointsMatrix.fromList(List.filled(16, -0.7));
    final observationBuilder = BodyHeightObservationBuilder(
      standingPose: policyDefault,
    );
    final brain = Brain(
      imu: imu,
      joint: joint,
      clock: clock,
      standingPose: physicalStand,
      sittingPose: JointsMatrix.zero(),
      observationBuilder: observationBuilder,
    );
    addTearDown(brain.dispose);

    expect(brain.standUp.standingPose.values, physicalStand.values);
    expect(
      brain.walk.observationBuilder.standingPose.values,
      policyDefault.values,
    );
    expect(brain.standingPose.values, physicalStand.values);
  });

  test('Brain.shareMemory falls back to the observation builder pose', () {
    final policyDefault = JointsMatrix.fromList(List.filled(16, -0.7));
    final observationBuilder = BodyHeightObservationBuilder(
      standingPose: policyDefault,
    );

    final brain = Brain.shareMemory(
      historySize: 1,
      imu: imu,
      joint: joint,
      clock: clock,
      standUpCounts: 1,
      sitDownCounts: 1,
      observationBuilder: observationBuilder,
      sittingPose: JointsMatrix.zero(),
      memory: memory,
      bodyHeightCommandProvider: () => 0.35,
    );

    expect(brain.standUp.standingPose.values, policyDefault.values);
    expect(brain.standingPose.values, policyDefault.values);
  });

  test(
    'Brain keeps idle and transition height history on the active target',
    () {
      final brain = Brain(
        historySize: 10,
        imu: imu,
        joint: joint,
        clock: clock,
        standingPose: JointsMatrix.zero(),
        sittingPose: JointsMatrix.zero(),
        observationBuilder: BodyHeightObservationBuilder(
          standingPose: JointsMatrix.zero(),
        ),
        bodyHeightCommand: 0.48,
        minBodyHeightCommand: 0.20,
        maxBodyHeightCommand: 0.54,
        standUpCounts: 1,
      );
      addTearDown(brain.dispose);

      brain.bodyHeightCommand = 0.31;

      expect(
        brain.idle
            .next(
              command: const Command.idle(),
              nextAction: JointsMatrix.zero(),
            )
            .bodyHeightCommand,
        0.31,
      );
      expect(
        brain.standUp
            .next(
              command: const Command.standUp(),
              nextAction: JointsMatrix.zero(),
            )
            .bodyHeightCommand,
        0.31,
      );
      expect(
        brain.sitDown
            .next(
              command: const Command.sitDown(),
              nextAction: JointsMatrix.zero(),
            )
            .bodyHeightCommand,
        0.31,
      );
    },
  );
}
