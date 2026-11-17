import 'dart:async';
import 'dart:io';

import 'package:thunder/thunder.dart';
import 'package:thunder/src/app/voice_announcer.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

class MockBrain extends Mock implements Brain {}

class MockGainManager extends Mock implements GainManager {}

class MockRealControlDog extends Mock implements RealControlDog {}

class RecordingPolicyVoice implements VoiceAnnouncer {
  final announcements = <VoiceAnnouncement>[];
  Future<void> Function()? onCall;

  @override
  Future<void> announce(VoiceAnnouncement announcement) async {
    announcements.add(announcement);
    await onCall?.call();
  }
}

final _pose1 = JointsMatrix.fromList(List.filled(16, 1.0));
final _pose2 = JointsMatrix.fromList(List.filled(16, 2.0));
final _kp1 = JointsMatrix.fromList(List.filled(16, 10.0));
final _kd1 = JointsMatrix.fromList(List.filled(16, 20.0));
final _kp2 = JointsMatrix.fromList(List.filled(16, 30.0));
final _kd2 = JointsMatrix.fromList(List.filled(16, 40.0));
final _operatorSlots = OperatorModeSlots.fromJson({
  'flat': 'flat_replacement_candidate',
  'stairs': 'stairs_replacement_candidate',
});

RobotProfile _profile(
  String name,
  JointsMatrix pose,
  JointsMatrix kp,
  JointsMatrix kd, {
  bool forceZeroWheelOnStop = true,
}) => RobotProfile(
  name: name,
  modelPath: 'model/$name.onnx',
  forceZeroWheelOnStop: forceZeroWheelOnStop,
  standingPose: pose,
  sittingPose: JointsMatrix.zero(),
  inferKp: kp,
  inferKd: kd,
  standUpKp: kp,
  standUpKd: kd,
  sitDownKp: kp,
  sitDownKd: kd,
);

void main() {
  late MockBrain brain;
  late MockGainManager gains;
  late MockRealControlDog controlDog;
  late Map<String, RobotProfile> profiles;

  setUpAll(() {
    registerFallbackValue(JointsMatrix.zero());
    registerFallbackValue(GestureLibrary(standingPose: JointsMatrix.zero()));
    registerFallbackValue(
      StandardObservationBuilder(standingPose: JointsMatrix.zero()),
    );
  });

  setUp(() {
    brain = MockBrain();
    gains = MockGainManager();
    controlDog = MockRealControlDog();

    profiles = {
      'alpha': _profile('alpha', _pose1, _kp1, _kd1),
      'beta': _profile('beta', _pose2, _kp2, _kd2),
    };

    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
      ),
    ).thenAnswer((_) async {});

    when(() => brain.gestureLibrary = any()).thenReturn(null);

    when(
      () => gains.switchGains(
        inferKp: any(named: 'inferKp'),
        inferKd: any(named: 'inferKd'),
        standUpKp: any(named: 'standUpKp'),
        standUpKd: any(named: 'standUpKd'),
        sitDownKp: any(named: 'sitDownKp'),
        sitDownKd: any(named: 'sitDownKd'),
      ),
    ).thenReturn(null);

    when(
      () => controlDog.switchGains(
        inferKp: any(named: 'inferKp'),
        inferKd: any(named: 'inferKd'),
        standUpKp: any(named: 'standUpKp'),
        standUpKd: any(named: 'standUpKd'),
        sitDownKp: any(named: 'sitDownKp'),
        sitDownKd: any(named: 'sitDownKd'),
      ),
    ).thenReturn(null);

    when(
      () => controlDog.switchCommandProfile(
        commandVxMax: any(named: 'commandVxMax'),
        commandVyMax: any(named: 'commandVyMax'),
        commandYawMax: any(named: 'commandYawMax'),
        forwardMinCommand: any(named: 'forwardMinCommand'),
        lateralMinCommand: any(named: 'lateralMinCommand'),
        yawMinCommand: any(named: 'yawMinCommand'),
      ),
    ).thenReturn(null);
  });

  group('successful switch voice', () {
    late RecordingPolicyVoice voice;

    ProfileManager manager({bool slots = true}) => ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      initial: 'alpha',
      voice: voice,
      operatorSlots: slots
          ? OperatorModeSlots.fromJson({'flat': 'alpha', 'stairs': 'beta'})
          : null,
    );

    setUp(() {
      voice = RecordingPolicyVoice();
      when(
        () => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          standUpCounts: any(named: 'standUpCounts'),
          sitDownCounts: any(named: 'sitDownCounts'),
          canCommit: any(named: 'canCommit'),
          preparedProfile: any(named: 'preparedProfile'),
        ),
      ).thenAnswer((_) async {});
    });

    test('initialization and unchanged profile are silent', () async {
      final pm = manager();
      expect(voice.announcements, isEmpty);
      await pm.switchTo('alpha');
      expect(voice.announcements, isEmpty);
    });

    test(
      'flat and stairs announce only after current profile commits',
      () async {
        final pm = manager();
        voice.onCall = () async {
          expect(pm.currentName, 'beta');
        };
        await pm.switchTo('beta');
        expect(voice.announcements.single.audioAsset, 'mode_stairs.wav');
        voice.onCall = () async {
          expect(pm.currentName, 'alpha');
        };
        await pm.switchTo('alpha');
        expect(voice.announcements.last.audioAsset, 'mode_flat.wav');
        expect(
          voice.announcements.every((a) => a.key == 'profile_switched'),
          isTrue,
        );
      },
    );

    test('other profiles use a generic success message', () async {
      await manager(slots: false).switchTo('beta');
      expect(voice.announcements.single.audioAsset, 'profile_changed.wav');
    });

    test('unknown profile never announces success', () async {
      await expectLater(manager().switchTo('missing'), throwsArgumentError);
      expect(voice.announcements, isEmpty);
    });

    test('cancelled commit and rollback never announce success', () async {
      final pm = manager();
      await expectLater(
        pm.switchTo('beta', canCommit: () => false),
        throwsStateError,
      );
      expect(pm.currentName, 'alpha');
      expect(voice.announcements, isEmpty);
    });

    test('model load failure never announces success', () async {
      when(
        () => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          standUpCounts: any(named: 'standUpCounts'),
          sitDownCounts: any(named: 'sitDownCounts'),
        ),
      ).thenThrow(StateError('model load failed'));
      final pm = manager();
      await expectLater(pm.switchTo('beta'), throwsStateError);
      expect(pm.currentName, 'alpha');
      expect(voice.announcements, isEmpty);
    });

    test('gain commit failure and successful rollback remain silent', () async {
      var calls = 0;
      when(
        () => gains.switchGains(
          inferKp: any(named: 'inferKp'),
          inferKd: any(named: 'inferKd'),
          standUpKp: any(named: 'standUpKp'),
          standUpKd: any(named: 'standUpKd'),
          sitDownKp: any(named: 'sitDownKp'),
          sitDownKd: any(named: 'sitDownKd'),
        ),
      ).thenAnswer((_) {
        if (++calls == 1) throw StateError('gain commit failed');
      });
      final pm = manager();
      await expectLater(pm.switchTo('beta'), throwsStateError);
      expect(pm.currentName, 'alpha');
      expect(pm.hasFault, isFalse);
      expect(voice.announcements, isEmpty);
    });

    test('voice failure cannot roll back a committed switch', () async {
      voice.onCall = () async => throw StateError('speaker disconnected');
      final pm = manager();
      await pm.switchTo('beta');
      await Future<void>.delayed(Duration.zero);
      expect(pm.currentName, 'beta');
      expect(pm.hasFault, isFalse);
    });

    test('voice playback never holds the switch transaction', () async {
      final release = Completer<void>();
      voice.onCall = () => release.future;
      final pm = manager();
      await pm.switchTo('beta').timeout(const Duration(seconds: 1));
      expect(pm.currentName, 'beta');
      expect(voice.announcements.length, 1);
      release.complete();
    });
  });

  test('switchTo forwards the per-profile wheel stop opt-out', () async {
    profiles['beta'] = _profile(
      'beta',
      _pose2,
      _kp2,
      _kd2,
      forceZeroWheelOnStop: false,
    );
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        forceZeroWheelOnStop: false,
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
      ),
    ).thenAnswer((_) async {});
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'alpha',
    );
    await pm.switchTo('beta');
    verify(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        forceZeroWheelOnStop: false,
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: 'model/beta.onnx',
        standUpCounts: 150,
        sitDownCounts: 150,
      ),
    ).called(1);
    expect(pm.currentName, 'beta');
  });

  test('initial state', () {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'alpha',
    );
    expect(pm.currentName, 'alpha');
    expect(pm.names, ['alpha', 'beta']);
  });

  test('switchTo calls brain.switchProfile and updates currentName', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.switchTo('beta');

    expect(pm.currentName, 'beta');
    verify(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: 'model/beta.onnx',
        standUpCounts: 150,
        sitDownCounts: 150,
      ),
    ).called(1);
  });

  test('switchTo updates GainManager gains', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      initial: 'alpha',
    );

    await pm.switchTo('beta');

    verify(
      () => gains.switchGains(
        inferKp: _kp2,
        inferKd: _kd2,
        standUpKp: _kp2,
        standUpKd: _kd2,
        sitDownKp: _kp2,
        sitDownKd: _kd2,
      ),
    ).called(1);
  });

  test('switchTo updates RealControlDog gains', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.switchTo('beta');

    verify(
      () => controlDog.switchGains(
        inferKp: _kp2,
        inferKd: _kd2,
        standUpKp: _kp2,
        standUpKd: _kd2,
        sitDownKp: _kp2,
        sitDownKd: _kd2,
      ),
    ).called(1);
  });

  test('switchTo updates RealControlDog command profile', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.switchTo('beta');

    verify(
      () => controlDog.switchCommandProfile(
        commandVxMax: 1.5,
        commandVyMax: 1.0,
        commandYawMax: 1.0,
        forwardMinCommand: 0.0,
        lateralMinCommand: 0.30,
        yawMinCommand: 0.40,
      ),
    ).called(1);
  });

  test('switchTo same profile is a no-op', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.switchTo('alpha');

    verifyNever(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
      ),
    );
  });

  test('switchTo unknown profile throws ArgumentError', () {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'alpha',
    );

    expect(() => pm.switchTo('unknown'), throwsArgumentError);
  });

  test('R2 cycles only accepted slots, never archived profiles', () async {
    final flat = _operatorSlots.profileNames[0];
    final stairs = _operatorSlots.profileNames[1];
    profiles[flat] = _profile(flat, _pose1, _kp1, _kd1);
    profiles[stairs] = _profile(stairs, _pose1, _kp1, _kd1);
    when(() => controlDog.canSwitchProfile).thenReturn(true);
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
        canCommit: any(named: 'canCommit'),
        preparedProfile: any(named: 'preparedProfile'),
      ),
    ).thenAnswer((_) async {});
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      initial: flat,
      operatorSlots: _operatorSlots,
    );

    await pm.toggle();
    expect(pm.currentName, stairs);

    await pm.toggle();
    expect(pm.currentName, flat);
  });

  test('R2 cycles three configured slots in order', () async {
    final slots = OperatorModeSlots.fromJson({
      'flat': 'flat_profile',
      'stairs': 'stairs_profile',
      'high_platform': 'platform_profile',
    });
    for (final name in slots.profileNames) {
      profiles[name] = _profile(name, _pose1, _kp1, _kd1);
    }
    when(() => controlDog.canSwitchProfile).thenReturn(true);
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
        canCommit: any(named: 'canCommit'),
        preparedProfile: any(named: 'preparedProfile'),
      ),
    ).thenAnswer((_) async {});
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: 'flat_profile',
      operatorSlots: slots,
    );
    for (final expected in [
      'stairs_profile',
      'platform_profile',
      'flat_profile',
    ]) {
      await pm.toggle();
      expect(pm.currentName, expected);
    }
  });

  test('gRPC operator names resolve aliases and bound profile names', () async {
    final slots = OperatorModeSlots.fromJson({
      'flat': 'flat_profile',
      'stairs': 'stairs_profile',
      'high_platform': 'platform_profile',
    });
    for (final name in slots.profileNames) {
      profiles[name] = _profile(name, _pose1, _kp1, _kd1);
    }
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
        canCommit: any(named: 'canCommit'),
        preparedProfile: any(named: 'preparedProfile'),
      ),
    ).thenAnswer((_) async {});
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'flat_profile',
      operatorSlots: slots,
    );
    expect(pm.operatorNames, [
      'flat_profile',
      'stairs_profile',
      'platform_profile',
    ]);
    expect(pm.operatorDescriptions.map((s) => s.split(':').first), [
      'flat',
      'stairs',
      'high_platform',
    ]);
    for (final entry in {
      'high_platform': 'platform_profile',
      'stairs': 'stairs_profile',
      'platform_profile': 'platform_profile',
      'flat': 'flat_profile',
    }.entries) {
      await pm.switchOperatorProfile(entry.key, canCommit: () => true);
      expect(pm.currentName, entry.value);
    }
    await expectLater(
      pm.switchOperatorProfile('alpha', canCommit: () => true),
      throwsArgumentError,
    );
    final legacy = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'flat_profile',
      operatorSlots: OperatorModeSlots.fromJson({
        'flat': 'flat_profile',
        'stairs': 'stairs_profile',
        'high_platform': null,
      }),
    );
    await expectLater(
      legacy.switchOperatorProfile('high_platform', canCommit: () => true),
      throwsArgumentError,
    );
  });

  test(
    'switchTo brain failure rolls back gains and keeps currentName',
    () async {
      when(
        () => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          standUpCounts: any(named: 'standUpCounts'),
          sitDownCounts: any(named: 'sitDownCounts'),
        ),
      ).thenThrow(Exception('model file not found'));

      final pm = ProfileManager(
        profiles: profiles,
        brain: brain,
        gains: gains,
        controlDog: controlDog,
        initial: 'alpha',
      );

      await expectLater(() => pm.switchTo('beta'), throwsException);

      // Name must not change — partial switch was rolled back
      expect(pm.currentName, 'alpha');

      // Gains must be rolled back to alpha
      verify(
        () => gains.switchGains(
          inferKp: _kp1,
          inferKd: _kd1,
          standUpKp: _kp1,
          standUpKd: _kd1,
          sitDownKp: _kp1,
          sitDownKd: _kd1,
        ),
      ).called(1);
      verify(
        () => controlDog.switchCommandProfile(
          commandVxMax: 1.5,
          commandVyMax: 1.0,
          commandYawMax: 1.0,
          forwardMinCommand: 0.0,
          lateralMinCommand: 0.30,
          yawMinCommand: 0.40,
        ),
      ).called(1);
    },
  );

  test('switchTo while already switching throws StateError', () async {
    // brain.switchProfile hangs until we release the completer
    final completer = Completer<void>();
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
      ),
    ).thenAnswer((_) => completer.future);

    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'alpha',
    );

    // Start first switch (will hang)
    final firstSwitch = pm.switchTo('beta');

    // Concurrent second switch → StateError
    await expectLater(() => pm.switchTo('beta'), throwsStateError);

    // Unblock first switch
    completer.complete();
    await firstSwitch;
  });

  test('onFault called when switch AND rollback both fail', () async {
    // brain.switchProfile fails on switch
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
      ),
    ).thenThrow(Exception('model corrupt'));

    // gains.switchGains fails on rollback
    when(
      () => gains.switchGains(
        inferKp: any(named: 'inferKp'),
        inferKd: any(named: 'inferKd'),
        standUpKp: any(named: 'standUpKp'),
        standUpKd: any(named: 'standUpKd'),
        sitDownKp: any(named: 'sitDownKp'),
        sitDownKd: any(named: 'sitDownKd'),
      ),
    ).thenThrow(Exception('gains rollback failed'));

    String? faultReason;
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      onFault: (reason) => faultReason = reason,
      initial: 'alpha',
    );

    await expectLater(() => pm.switchTo('beta'), throwsException);

    expect(faultReason, isNotNull);
    expect(faultReason, contains('rollback'));
    expect(pm.hasFault, isTrue);
    await expectLater(pm.switchTo('alpha'), throwsStateError);
  });

  for (final problem in [
    'missing',
    'unaccepted current',
    'different standing',
    'not L1 standing',
  ]) {
    test('R2 rejects $problem without fallback', () async {
      final flat = _operatorSlots.profileNames[0];
      final stairs = _operatorSlots.profileNames[1];
      when(
        () => controlDog.canSwitchProfile,
      ).thenReturn(problem != 'not L1 standing');
      profiles[flat] = _profile(flat, _pose1, _kp1, _kd1);
      if (problem != 'missing') {
        profiles[stairs] = _profile(
          stairs,
          problem == 'different standing' ? _pose2 : _pose1,
          _kp1,
          _kd1,
        );
      }
      final pm = ProfileManager(
        profiles: profiles,
        brain: brain,
        controlDog: controlDog,
        initial: problem == 'unaccepted current' ? 'alpha' : flat,
        operatorSlots: _operatorSlots,
      );
      await expectLater(pm.toggle(), throwsStateError);
      expect(pm.currentName, problem == 'unaccepted current' ? 'alpha' : flat);
      verifyNever(
        () => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          canCommit: any(named: 'canCommit'),
          preparedProfile: any(named: 'preparedProfile'),
        ),
      );
    });
  }

  test('failure after model commit also restores the previous Brain', () async {
    final switchedModels = <String>[];
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
        canCommit: any(named: 'canCommit'),
        preparedProfile: any(named: 'preparedProfile'),
      ),
    ).thenAnswer((invocation) async {
      switchedModels.add(invocation.namedArguments[#modelPath] as String);
    });
    var attempt = 0;
    when(
      () => controlDog.switchCommandProfile(
        commandVxMax: any(named: 'commandVxMax'),
        commandVyMax: any(named: 'commandVyMax'),
        commandYawMax: any(named: 'commandYawMax'),
        forwardMinCommand: any(named: 'forwardMinCommand'),
        lateralMinCommand: any(named: 'lateralMinCommand'),
        yawMinCommand: any(named: 'yawMinCommand'),
      ),
    ).thenAnswer((_) {
      if (attempt++ == 0) throw StateError('commit failed');
    });
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: 'alpha',
    );
    await expectLater(pm.switchTo('beta'), throwsStateError);
    expect(pm.currentName, 'alpha');
    expect(switchedModels, ['model/beta.onnx', 'model/alpha.onnx']);
  });

  test(
    'R2 without the accepted pair fails without loading another model',
    () async {
      final pm = ProfileManager(
        profiles: {'only': profiles['alpha']!},
        brain: brain,
        initial: 'only',
      );

      await expectLater(pm.toggle(), throwsStateError);
      expect(pm.currentName, 'only');
    },
  );

  group('reload', () {
    /// 写入一条最小合法 profile JSON 文件到 [dir]/[name].json。
    Future<void> writeProfileJson(Directory dir, String name) async {
      const zeros16 = '[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]';
      final json =
          '{'
          '"name":"$name","modelPath":"$name.onnx",'
          '"standingPose":$zeros16,"sittingPose":$zeros16,'
          '"inferKp":$zeros16,"inferKd":$zeros16,'
          '"standUpKp":$zeros16,"standUpKd":$zeros16,'
          '"sitDownKp":$zeros16,"sitDownKd":$zeros16'
          '}';
      await File('${dir.path}/$name.json').writeAsString(json);
    }

    test(
      'reload pins configured slots even when their files change or disappear',
      () async {
        final flat = _operatorSlots.flat;
        final stairs = _operatorSlots.stairs;
        final directory = await Directory.systemTemp.createTemp('pm_slots_');
        try {
          profiles[flat] = _profile(flat, _pose1, _kp1, _kd1);
          profiles[stairs] = _profile(stairs, _pose1, _kp1, _kd1);
          when(() => controlDog.canSwitchProfile).thenReturn(true);
          when(
            () => brain.switchProfile(
              observationBuilder: any(named: 'observationBuilder'),
              forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
              standingPose: any(named: 'standingPose'),
              sittingPose: any(named: 'sittingPose'),
              modelPath: any(named: 'modelPath'),
              standUpCounts: any(named: 'standUpCounts'),
              sitDownCounts: any(named: 'sitDownCounts'),
              canCommit: any(named: 'canCommit'),
              preparedProfile: any(named: 'preparedProfile'),
            ),
          ).thenAnswer((_) async {});
          final pm = ProfileManager(
            profiles: profiles,
            brain: brain,
            controlDog: controlDog,
            initial: flat,
            operatorSlots: _operatorSlots,
          );
          // Disk now contains incompatible flat metadata and no stairs file.
          await writeProfileJson(directory, flat);
          await pm.reload(directory.path);
          expect(pm.names, containsAll([flat, stairs]));
          await pm.toggle();
          expect(pm.currentName, stairs);
          verify(
            () => controlDog.switchGains(
              inferKp: _kp1,
              inferKd: _kd1,
              standUpKp: _kp1,
              standUpKd: _kd1,
              sitDownKp: _kp1,
              sitDownKd: _kd1,
            ),
          ).called(1);
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );

    test('reload adds profiles newly added to disk', () async {
      final dir = await Directory.systemTemp.createTemp('pm_test_');
      try {
        await writeProfileJson(dir, 'alpha');
        await writeProfileJson(dir, 'beta');

        final pm = ProfileManager(
          profiles: {'alpha': profiles['alpha']!},
          brain: brain,
          initial: 'alpha',
        );
        expect(pm.names, ['alpha']);

        await pm.reload(dir.path);
        expect(pm.names, containsAll(['alpha', 'beta']));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test(
      'reload removes profiles deleted from disk, never removes current',
      () async {
        final dir = await Directory.systemTemp.createTemp('pm_test_');
        try {
          // Disk only has alpha and beta — gamma was deleted
          await writeProfileJson(dir, 'alpha');
          await writeProfileJson(dir, 'beta');

          final pm = ProfileManager(
            profiles: {
              'alpha': profiles['alpha']!,
              'beta': profiles['beta']!,
              'gamma': _profile('gamma', _pose1, _kp1, _kd1),
            },
            brain: brain,
            initial: 'alpha',
          );
          expect(pm.names, containsAll(['alpha', 'beta', 'gamma']));

          await pm.reload(dir.path);

          expect(pm.names, isNot(contains('gamma'))); // 磁盘上已删除
          expect(pm.names, containsAll(['alpha', 'beta']));
          expect(pm.currentName, 'alpha'); // 当前策略不受影响
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'reload does not remove current profile even if absent from disk',
      () async {
        final dir = await Directory.systemTemp.createTemp('pm_test_');
        try {
          // Disk only has beta — alpha (current) is absent
          await writeProfileJson(dir, 'beta');

          final pm = ProfileManager(
            profiles: {'alpha': profiles['alpha']!, 'beta': profiles['beta']!},
            brain: brain,
            initial: 'alpha',
          );

          await pm.reload(dir.path);

          // alpha is current → 即使磁盘上不存在也不能移除
          expect(pm.names, contains('alpha'));
          expect(pm.currentName, 'alpha');
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  });
}
