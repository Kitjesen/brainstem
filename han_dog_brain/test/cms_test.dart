import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_brain/src/behaviour.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vector_math/vector_math.dart';

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

void main() {
  setUpAll(() {
    registerFallbackValue(FakeHistory());
    registerFallbackValue(Vector3.zero()); // for Walk.doing(any())
  });

  blocTest(
    'zero state',
    build: () => TestM(),
    verify: (m) => expect(m.state, const Zero()),
  );

  blocTest(
    'init → grounded',
    build: () {
      final m = TestM();
      final mockBrain = m.mockBrain;
      when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
      when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());
      when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
      return m;
    },
    act: (m) => m.add(Init()),
    expect: () => [predicate((S s) => s is Grounded)],
  );

  () {
    final standUpSequence = <JointsMatrix>[
      .zero(),
      .fromList(.filled(16, 0.5)),
      .fromList(.filled(16, 1.0)),
    ].map(fakeStandUp).toList();
    blocTest(
      'grounded → standUp transition → standing',
      build: () {
        final m = TestM();
        final mockBrain = m.mockBrain;
        when(() => mockBrain.standUp).thenReturn(mockBrain.mockStandUp);
        when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
        when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);

        when(
          () => mockBrain.mockStandUp.doing,
        ).thenAnswer((_) => .fromIterable(standUpSequence));
        when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());
        return m;
      },
      seed: () => Grounded(Stream<History>.empty().listen((_) {})),
      act: (m) => m.add(const A.standUp()),
      expect: () => [
        predicate((S s) => s is Transitioning && s.target is StandUpCommand),
        predicate((S s) => s is Standing),
      ],
      verify: (m) {
        expect(
          verify(() => m.mockBrain.mockMemory.add(captureAny())).captured,
          standUpSequence,
        );
      },
    );
  }();

  () {
    final standUpSequence = <JointsMatrix>[
      .zero(),
      .fromList(.filled(16, 0.5)),
      .fromList(.filled(16, 1.0)),
    ].map(fakeStandUp).toList();

    final sitDownSequence = <JointsMatrix>[
      .fromList(.filled(16, 3.0)),
      .fromList(.filled(16, 2.0)),
      .fromList(.filled(16, 1.5)),
    ].map(fakeSitDown).toList();

    blocTest(
      'walking → sitDown (compound: standUp then sitDown)',
      build: () {
        final m = TestM();
        final mockBrain = m.mockBrain;
        when(() => mockBrain.standUp).thenReturn(mockBrain.mockStandUp);
        when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
        when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
        when(() => mockBrain.sitDown).thenReturn(mockBrain.mockSitDown);
        when(
          () => mockBrain.mockStandUp.doing,
        ).thenAnswer((_) => .fromIterable(standUpSequence));
        when(
          () => mockBrain.mockSitDown.doing,
        ).thenAnswer((_) => .fromIterable(sitDownSequence));
        when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());
        return m;
      },
      seed: () => Walking(Stream<History>.empty().listen((_) {})),
      act: (m) => m.add(const A.sitDown()),
      expect: () => [
        // Walking → Transitioning(StandUp, pending: SitDown)
        predicate((S s) =>
            s is Transitioning &&
            s.target is StandUpCommand &&
            s.pending is CmdSitDown),
        // StandUp done → Transitioning(SitDown)
        predicate((S s) =>
            s is Transitioning &&
            s.target is SitDownCommand &&
            s.pending == null),
        // SitDown done → Grounded
        predicate((S s) => s is Grounded),
      ],
      verify: (m) {
        expect(
          verify(() => m.mockBrain.mockMemory.add(captureAny())).captured,
          [...standUpSequence, ...sitDownSequence],
        );
      },
    );
  }();

  () {
    blocTest(
      'standing → standUp is no-op',
      build: () => TestM(),
      seed: () => Standing(Stream<History>.empty().listen((_) {})),
      act: (m) => m.add(const A.standUp()),
      expect: () => <S>[],
    );
  }();

  // ── Zero 状态保护 ─────────────────────────────────────────

  blocTest(
    'zero + non-Init command → ignored',
    build: () => TestM(),
    act: (m) => m.add(const A.standUp()),
    expect: () => <S>[],
  );

  // ── Init 重入 ─────────────────────────────────────────────

  blocTest(
    'init re-entry in Standing → ignored',
    build: () => TestM(),
    seed: () => Standing(Stream<History>.empty().listen((_) {})),
    act: (m) => m.add(const A.init()),
    expect: () => <S>[],
  );

  // ── Fault 安全路径 ────────────────────────────────────────

  blocTest(
    'grounded + fault → safe (no state change)',
    build: () => TestM(),
    seed: () => Grounded(Stream<History>.empty().listen((_) {})),
    act: (m) => m.add(A.fault('test error')),
    expect: () => <S>[],
  );

  blocTest(
    'standing + fault → safe (no state change)',
    build: () => TestM(),
    seed: () => Standing(Stream<History>.empty().listen((_) {})),
    act: (m) => m.add(A.fault('test error')),
    expect: () => <S>[],
  );

  // ── Standing → SitDown ───────────────────────────────────

  () {
    final sitDownSequence = <JointsMatrix>[
      .fromList(.filled(16, 1.0)),
      .fromList(.filled(16, 0.5)),
      .zero(),
    ].map(fakeSitDown).toList();

    blocTest(
      'standing → sitDown → grounded',
      build: () {
        final m = TestM();
        final mockBrain = m.mockBrain;
        when(() => mockBrain.sitDown).thenReturn(mockBrain.mockSitDown);
        when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
        when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
        when(
          () => mockBrain.mockSitDown.doing,
        ).thenAnswer((_) => .fromIterable(sitDownSequence));
        when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());
        return m;
      },
      seed: () => Standing(Stream<History>.empty().listen((_) {})),
      act: (m) => m.add(const A.sitDown()),
      expect: () => [
        predicate((S s) => s is Transitioning && s.target is SitDownCommand),
        predicate((S s) => s is Grounded),
      ],
    );
  }();

  // ── Walking → CmdIdle ────────────────────────────────────

  () {
    final standUpSequence = <JointsMatrix>[
      .zero(),
      .fromList(.filled(16, 0.5)),
      .fromList(.filled(16, 1.0)),
    ].map(fakeStandUp).toList();

    blocTest(
      'walking → idle → standing',
      build: () {
        final m = TestM();
        final mockBrain = m.mockBrain;
        when(() => mockBrain.standUp).thenReturn(mockBrain.mockStandUp);
        when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
        when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
        when(
          () => mockBrain.mockStandUp.doing,
        ).thenAnswer((_) => .fromIterable(standUpSequence));
        when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());
        return m;
      },
      seed: () => Walking(Stream<History>.empty().listen((_) {})),
      act: (m) => m.add(const A.idle()),
      expect: () => [
        predicate((S s) => s is Transitioning && s.target is StandUpCommand),
        predicate((S s) => s is Standing),
      ],
    );
  }();

  // ── Transitioning + Fault 安全路径 ───────────────────────

  () {
    final sitDownSequence = <JointsMatrix>[
      .fromList(.filled(16, 1.0)),
      .fromList(.filled(16, 0.5)),
      .zero(),
    ].map(fakeSitDown).toList();

    blocTest(
      'transitioning standUp + fault → sitDown → grounded',
      build: () {
        final m = TestM();
        final mockBrain = m.mockBrain;
        when(() => mockBrain.sitDown).thenReturn(mockBrain.mockSitDown);
        when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
        when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
        when(
          () => mockBrain.mockSitDown.doing,
        ).thenAnswer((_) => .fromIterable(sitDownSequence));
        when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());
        return m;
      },
      seed: () => Transitioning(
        const Command.standUp(),
        Stream<History>.empty().listen((_) {}),
        null,
      ),
      act: (m) => m.add(A.fault('StandUp hardware error')),
      expect: () => [
        predicate((S s) => s is Transitioning && s.target is SitDownCommand),
        predicate((S s) => s is Grounded),
      ],
    );
  }();

  // ── Walk 流意外关闭 ────────────────────────────────────────

  () {
    final standUpSequence = <JointsMatrix>[
      .fromList(.filled(16, 1.0)),
    ].map(fakeStandUp).toList();

    blocTest(
      'walk stream closes unexpectedly → fault → standUp → standing',
      build: () {
        final m = TestM();
        final mockBrain = m.mockBrain;
        when(() => mockBrain.walk).thenReturn(mockBrain.mockWalk);
        when(() => mockBrain.standUp).thenReturn(mockBrain.mockStandUp);
        when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
        when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
        // Walk stream closes immediately (simulates clock interruption)
        when(() => mockBrain.mockWalk.doing(any()))
            .thenAnswer((_) => Stream.empty());
        when(() => mockBrain.mockStandUp.doing)
            .thenAnswer((_) => Stream.fromIterable(standUpSequence));
        when(() => mockBrain.mockIdle.doing).thenAnswer((_) => Stream.empty());
        return m;
      },
      // Seed from Standing so that CmdWalk calls _listenWalk (which registers onDone).
      // Seeding directly as Walking would bypass _listenWalk and its onDone handler.
      seed: () => Standing(Stream<History>.empty().listen((_) {})),
      act: (m) async {
        m.add(A.walk(Vector3.zero())); // Standing → Walking via _listenWalk
        // Walk stream (Stream.empty) closes → onDone fires → Fault via microtask
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      expect: () => [
        predicate((S s) => s is Walking),
        predicate((S s) => s is Transitioning && s.target is StandUpCommand),
        predicate((S s) => s is Standing),
      ],
    );
  }();

  // ── Idle 流意外关闭 ────────────────────────────────────────

  () {
    final standUpSequence = <JointsMatrix>[
      .fromList(.filled(16, 1.0)),
    ].map(fakeStandUp).toList();

    blocTest(
      'idle stream closes after standUp → fault → standing stays (safe)',
      build: () {
        final m = TestM();
        final mockBrain = m.mockBrain;
        when(() => mockBrain.standUp).thenReturn(mockBrain.mockStandUp);
        when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
        when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
        when(() => mockBrain.mockStandUp.doing)
            .thenAnswer((_) => Stream.fromIterable(standUpSequence));
        // Idle stream closes immediately — simulates clock stream interruption
        when(() => mockBrain.mockIdle.doing)
            .thenAnswer((_) => Stream.empty());
        return m;
      },
      seed: () => Grounded(Stream<History>.empty().listen((_) {})),
      act: (m) async {
        m.add(const A.standUp());
        // Allow standUp to complete and idle's onDone fault to be processed
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      expect: () => [
        predicate((S s) => s is Transitioning && s.target is StandUpCommand),
        predicate((S s) => s is Standing),
        // fault from idle onDone arrives → Standing + fault = no state change
      ],
    );
  }();

  blocTest(
    'transitioning sitDown + fault → forced grounded (no dead loop)',
    build: () {
      final m = TestM();
      final mockBrain = m.mockBrain;
      when(() => mockBrain.idle).thenReturn(mockBrain.mockIdle);
      when(() => mockBrain.memory).thenReturn(mockBrain.mockMemory);
      when(() => mockBrain.mockIdle.doing).thenAnswer((_) => .empty());
      return m;
    },
    seed: () => Transitioning(
      const Command.sitDown(),
      Stream<History>.empty().listen((_) {}),
      null,
    ),
    act: (m) => m.add(A.fault('SitDown hardware error')),
    expect: () => [
      predicate((S s) => s is Grounded),
    ],
  );
}

History fakeStandUp(JointsMatrix nextAction) => History(
  gyroscope: .zero(),
  projectedGravity: .zero(),
  command: .standUp(),
  jointPosition: .zero(),
  jointVelocity: .zero(),
  action: .zero(),
  nextAction: nextAction,
);

History fakeSitDown(JointsMatrix nextAction) => History(
  gyroscope: .zero(),
  projectedGravity: .zero(),
  command: .sitDown(),
  jointPosition: .zero(),
  jointVelocity: .zero(),
  action: .zero(),
  nextAction: nextAction,
);
