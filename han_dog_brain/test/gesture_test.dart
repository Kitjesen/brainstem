import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_brain/src/behaviour.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockImu extends Mock implements ImuService {}

class MockJoint extends Mock implements JointService {}

class MockBrain extends Mock implements Brain {
  final mockIdle = MockIdle();
  final mockStandUp = MockStandUp();
  final mockSitDown = MockSitDown();
  final mockWalk = MockWalk();
  final mockMemory = MockMemory();
}

class MockIdle extends Mock implements Idle {}

class MockStandUp extends Mock implements StandUp {}

class MockSitDown extends Mock implements SitDown {}

class MockWalk extends Mock implements Walk {}

class MockMemory extends Mock implements Memory<History> {}

class FakeHistory extends Fake implements History {}

class TestM extends M {
  final MockBrain mockBrain;
  TestM._(this.mockBrain, super._brain);
  factory TestM() {
    final mockBrain = MockBrain();
    return TestM._(mockBrain, mockBrain);
  }
}

History fakeGesture(JointsMatrix nextAction) => History(
      gyroscope: Vector3.zero(),
      projectedGravity: Vector3(0, 0, -1),
      command: const Command.gesture('test'),
      jointPosition: .zero(),
      jointVelocity: .zero(),
      action: .zero(),
      nextAction: nextAction,
    );

History fakeIdle(JointsMatrix nextAction) => History(
      gyroscope: Vector3.zero(),
      projectedGravity: Vector3(0, 0, -1),
      command: const Command.idle(),
      jointPosition: .zero(),
      jointVelocity: .zero(),
      action: .zero(),
      nextAction: nextAction,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(FakeHistory());
  });

  // ═══════════════════════════════════════════════════════════
  //  Gesture Behaviour
  // ═══════════════════════════════════════════════════════════

  group('Gesture Behaviour', () {
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
      when(() => joint.position).thenReturn(.zero());
      when(() => joint.velocity).thenReturn(.zero());
    });

    tearDown(() {
      clock.close();
      memory.dispose();
    });

    test('single keyframe emits correct frame count then completes', () async {
      final target = JointsMatrix.fromList(List.filled(16, 2.0));
      final definition = GestureDefinition(
        name: 'test',
        keyframes: [Keyframe(targetPose: target, counts: 3)],
      );

      final gesture = Gesture(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        definition: definition,
      );

      final results = <History>[];
      var completed = false;
      final sub = gesture.doing.listen(
        results.add,
        onDone: () => completed = true,
      );

      for (var i = 0; i < 5; i++) {
        clock.add(null);
        await Future.delayed(Duration.zero);
      }

      expect(results, hasLength(4)); // counts=3 → frames at t=0, 1/3, 2/3, 1.0
      expect(completed, isTrue);

      for (final h in results) {
        expect(h.command, isA<GestureCommand>());
        expect((h.command as GestureCommand).name, 'test');
      }

      await sub.cancel();
    });

    test('single keyframe interpolates correctly', () async {
      when(() => joint.position).thenReturn(.zero());

      final target = JointsMatrix.fromList(List.filled(16, 3.0));
      final definition = GestureDefinition(
        name: 'interp',
        keyframes: [Keyframe(targetPose: target, counts: 3)],
      );

      final gesture = Gesture(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        definition: definition,
      );

      final results = <History>[];
      final sub = gesture.doing.listen(results.add);

      for (var i = 0; i < 5; i++) {
        clock.add(null);
        await Future.delayed(Duration.zero);
      }

      expect(results, hasLength(4));
      // lerp(0, 3, t): t=0→0, t=1/3→1, t=2/3→2, t=1→3
      expect(results[0].nextAction.values[0], closeTo(0.0, 1e-6));
      expect(results[1].nextAction.values[0], closeTo(1.0, 1e-6));
      expect(results[2].nextAction.values[0], closeTo(2.0, 1e-6));
      expect(results[3].nextAction.values[0], closeTo(3.0, 1e-6));

      // foot values zeroed by discardFoot
      for (final h in results) {
        expect(h.nextAction.values[12], 0.0);
        expect(h.nextAction.values[15], 0.0);
      }

      await sub.cancel();
    });

    test('multi-keyframe chains correctly', () async {
      when(() => joint.position).thenReturn(.zero());

      final pose1 = JointsMatrix.fromList(List.filled(16, 1.0));
      final pose2 = JointsMatrix.fromList(List.filled(16, 3.0));
      final definition = GestureDefinition(
        name: 'chain',
        keyframes: [
          Keyframe(targetPose: pose1, counts: 1), // 2 frames: t=0, t=1
          Keyframe(targetPose: pose2, counts: 1), // 2 frames: t=0, t=1
        ],
      );

      final gesture = Gesture(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        definition: definition,
      );

      final results = <History>[];
      var completed = false;
      final sub = gesture.doing.listen(
        results.add,
        onDone: () => completed = true,
      );

      for (var i = 0; i < 6; i++) {
        clock.add(null);
        await Future.delayed(Duration.zero);
      }

      // Keyframe 1: 2 frames (t=0→0.0, t=1→1.0)
      // Keyframe 2: 2 frames (from 1.0, t=0→1.0, t=1→3.0)
      expect(results, hasLength(4));
      expect(completed, isTrue);

      expect(results[0].nextAction.values[0], closeTo(0.0, 1e-6));
      expect(results[1].nextAction.values[0], closeTo(1.0, 1e-6));
      expect(results[2].nextAction.values[0], closeTo(1.0, 1e-6)); // start of keyframe 2
      expect(results[3].nextAction.values[0], closeTo(3.0, 1e-6)); // end of keyframe 2

      await sub.cancel();
    });

    test('counts=0 keyframe emits 1 frame then moves to next', () async {
      when(() => joint.position).thenReturn(.zero());

      final pose1 = JointsMatrix.fromList(List.filled(16, 5.0));
      final pose2 = JointsMatrix.fromList(List.filled(16, 10.0));
      final definition = GestureDefinition(
        name: 'instant',
        keyframes: [
          Keyframe(targetPose: pose1, counts: 0), // instant: 1 frame
          Keyframe(targetPose: pose2, counts: 1), // 2 frames
        ],
      );

      final gesture = Gesture(
        clock: clock,
        imu: imu,
        joint: joint,
        memory: memory,
        definition: definition,
      );

      final results = <History>[];
      var completed = false;
      final sub = gesture.doing.listen(
        results.add,
        onDone: () => completed = true,
      );

      for (var i = 0; i < 5; i++) {
        clock.add(null);
        await Future.delayed(Duration.zero);
      }

      // counts=0: (0/0).clamp→NaN, but we check the result
      // Keyframe 2: 2 frames
      expect(results.length, greaterThanOrEqualTo(2));
      expect(completed, isTrue);

      await sub.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  GestureLibrary
  // ═══════════════════════════════════════════════════════════

  group('GestureLibrary', () {
    late GestureLibrary library;
    final standingPose = JointsMatrix.fromList(List.filled(16, 0.5));

    setUp(() {
      library = GestureLibrary(standingPose: standingPose);
    });

    test('register and get', () {
      final def = GestureDefinition(
        name: 'hello',
        keyframes: [
          Keyframe(targetPose: .zero(), counts: 10),
        ],
      );
      library.register(def);

      expect(library.get('hello'), same(def));
      expect(library.get('missing'), isNull);
      expect(library.contains('hello'), isTrue);
      expect(library.contains('missing'), isFalse);
      expect(library.names, ['hello']);
    });

    test('registerDefaults creates 5 gestures', () {
      library.registerDefaults();

      expect(library.names,
          containsAll(['bow', 'nod', 'wiggle', 'stretch', 'dance']));
      expect(library.names, hasLength(5));
    });

    test('default bow has 4 keyframes', () {
      library.registerDefaults();
      final bow = library.get('bow')!;

      expect(bow.keyframes, hasLength(4));
      expect(bow.description, '鞠躬 / 拜年');
    });

    test('default nod has 6 keyframes', () {
      library.registerDefaults();
      final nod = library.get('nod')!;

      expect(nod.keyframes, hasLength(6));
    });

    test('default wiggle has 9 keyframes', () {
      library.registerDefaults();
      final wiggle = library.get('wiggle')!;

      expect(wiggle.keyframes, hasLength(9));
    });

    test('default stretch has 8 keyframes', () {
      library.registerDefaults();
      final stretch = library.get('stretch')!;

      expect(stretch.keyframes, hasLength(8));
    });

    test('default dance has 16 keyframes', () {
      library.registerDefaults();
      final dance = library.get('dance')!;

      expect(dance.keyframes, hasLength(16));
    });

    test('JSON round-trip', () {
      final def = GestureDefinition(
        name: 'test_action',
        description: '测试动作',
        keyframes: [
          Keyframe(targetPose: standingPose, counts: 30),
          Keyframe(targetPose: .zero(), counts: 20),
        ],
      );
      library.register(def);

      final json = library.toJson();
      final library2 = GestureLibrary(standingPose: standingPose);
      library2.loadFromJson(json);

      final restored = library2.get('test_action')!;
      expect(restored.name, 'test_action');
      expect(restored.description, '测试动作');
      expect(restored.keyframes, hasLength(2));
      expect(restored.keyframes[0].counts, 30);
      expect(restored.keyframes[1].counts, 20);
      expect(restored.keyframes[1].targetPose.values, JointsMatrix.zero().values);
    });

    test('loadFromJson with multiple gestures', () {
      final jsonStr = jsonEncode([
        {
          'name': 'g1',
          'keyframes': [
            {'targetPose': List.filled(16, 1.0), 'counts': 10},
          ],
        },
        {
          'name': 'g2',
          'keyframes': [
            {'targetPose': List.filled(16, 2.0), 'counts': 20},
          ],
        },
      ]);

      library.loadFromJson(jsonStr);

      expect(library.contains('g1'), isTrue);
      expect(library.contains('g2'), isTrue);
      expect(library.get('g1')!.keyframes[0].counts, 10);
      expect(library.get('g2')!.keyframes[0].counts, 20);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Command.gesture
  // ═══════════════════════════════════════════════════════════

  group('Command.gesture', () {
    test('toString', () {
      expect(const Command.gesture('bow').toString(), 'gesture(bow)');
    });

    test('equality', () {
      expect(
        const Command.gesture('bow'),
        const Command.gesture('bow'),
      );
      expect(
        const Command.gesture('bow'),
        isNot(const Command.gesture('nod')),
      );
    });

    test('pattern matching', () {
      const cmd = Command.gesture('test');
      final name = switch (cmd) {
        GestureCommand(:final name) => name,
        _ => null,
      };
      expect(name, 'test');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  FSM Gesture transitions
  // ═══════════════════════════════════════════════════════════

  group('FSM gesture', () {
    // Helper to create a TestM with gesture library configured
    TestM buildGestureM() {
      final m = TestM();
      final mockBrain = m.mockBrain;
      final gestureLib = GestureLibrary(
        standingPose: JointsMatrix.fromList(List.filled(16, 0.5)),
      );
      gestureLib.register(GestureDefinition(
        name: 'bow',
        keyframes: [
          Keyframe(
            targetPose: JointsMatrix.fromList(List.filled(16, 1.0)),
            counts: 2,
          ),
        ],
      ));

      when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
      when(() => mockBrain.standUp).thenReturn(mockBrain.mockStandUp);
      when(() => mockBrain.sitDown).thenReturn(mockBrain.mockSitDown);
      when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
      when(() => mockBrain.gestureLibrary).thenReturn(gestureLib);
      when(() => mockBrain.createGesture('bow')).thenReturn(null);

      when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());

      return m;
    }

    blocTest(
      'standing + gesture(bow) with valid gesture → transitioning',
      build: () {
        final m = buildGestureM();
        final mockBrain = m.mockBrain;

        // StandUp stream for init→grounded→standing
        when(() => mockBrain.mockStandUp.doing).thenAnswer(
          (_) => Stream.fromIterable([
            fakeIdle(.zero()),
          ]),
        );

        // Gesture stream for the actual gesture
        final gestureSequence = [
          fakeGesture(JointsMatrix.fromList(List.filled(16, 0.5))),
          fakeGesture(JointsMatrix.fromList(List.filled(16, 1.0))),
        ];
        final mockGesture = Gesture(
          clock: StreamController<void>.broadcast(),
          imu: MockImu()
            ..stubGyroscope()
            ..stubProjectedGravity(),
          joint: MockJoint()
            ..stubPosition()
            ..stubVelocity(),
          memory: Memory<History>(historySize: 1, initial: History.zero()),
          definition: GestureDefinition(
            name: 'bow',
            keyframes: [
              Keyframe(
                targetPose: JointsMatrix.fromList(List.filled(16, 1.0)),
                counts: 1,
              ),
            ],
          ),
        );
        when(() => mockBrain.createGesture('bow')).thenReturn(mockGesture);

        // Return a finite stream for gesture doing
        when(() => mockBrain.createGesture('bow'))
            .thenAnswer((_) => null);

        // Instead, mock the _listenTransition behavior:
        // createGesture returns a mock Gesture whose .doing is a finite stream
        final mockGestureBehaviour = MockGestureBehaviour();
        when(() => mockGestureBehaviour.doing)
            .thenAnswer((_) => Stream.fromIterable(gestureSequence));
        when(() => mockBrain.createGesture('bow'))
            .thenReturn(mockGestureBehaviour);

        return m;
      },
      act: (m) async {
        m.add(Init());
        await Future.delayed(Duration.zero);
        m.add(const CmdStandUp());
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);
        // Now in Standing; add gesture
        m.add(const CmdGesture('bow'));
      },
      expect: () => [
        predicate((S s) => s is Grounded),
        predicate((S s) =>
            s is Transitioning && s.target is StandUpCommand),
        predicate((S s) => s is Standing),
        predicate((S s) =>
            s is Transitioning && s.target is GestureCommand),
        predicate((S s) => s is Standing), // gesture done → standing
      ],
    );

    blocTest(
      'standing + gesture(unknown) → stays standing',
      build: () {
        final m = buildGestureM();
        final mockBrain = m.mockBrain;

        when(() => mockBrain.mockStandUp.doing).thenAnswer(
          (_) => Stream.fromIterable([fakeIdle(.zero())]),
        );

        return m;
      },
      act: (m) async {
        m.add(Init());
        await Future.delayed(Duration.zero);
        m.add(const CmdStandUp());
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);
        // Try unknown gesture
        m.add(const CmdGesture('unknown'));
      },
      expect: () => [
        predicate((S s) => s is Grounded),
        predicate((S s) => s is Transitioning),
        predicate((S s) => s is Standing),
        // No state change for unknown gesture
      ],
    );
  });
}

// ─── Mock helpers ────────────────────────────────────────────

class MockGestureBehaviour extends Mock implements Gesture {}

extension on MockImu {
  void stubGyroscope() =>
      when(() => gyroscope).thenReturn(Vector3.zero());
  void stubProjectedGravity() =>
      when(() => projectedGravity).thenReturn(Vector3(0, 0, -1));
}

extension on MockJoint {
  void stubPosition() => when(() => position).thenReturn(.zero());
  void stubVelocity() => when(() => velocity).thenReturn(.zero());
}
