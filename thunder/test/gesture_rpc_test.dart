import 'dart:async';
import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:thunder/src/recovery/normal_recovery_runtime.dart';
import 'package:thunder/src/recovery/recovery.dart';
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';

class _Brain extends Mock implements Brain {}

class _Machine extends Mock implements M {}

class _Call extends Mock implements ServiceCall {}

class _Joint extends Mock implements RealJoint {}

class _Inference implements RecoveryInference {
  @override
  Future<List<double>> infer(int epoch, int seq, RecoverySample sample) async {
    return List<double>.filled(16, 0);
  }

  @override
  Future<void> reset(int epoch) async {}
}

void main() {
  late _Brain brain;
  late _Machine machine;
  late _Call call;
  late GestureLibrary library;
  late StreamSubscription<History> sub;

  setUpAll(() {
    registerFallbackValue(const A.init());
    registerFallbackValue(JointsMatrix.zero());
  });

  setUp(() {
    brain = _Brain();
    machine = _Machine();
    call = _Call();
    sub = Stream<History>.empty().listen((_) {});
    library = GestureLibrary(standingPose: JointsMatrix.zero())
      ..registerDefaults();
    library.tryLoadOnboard(
      catalogPath: _fixture('gesture_index.json').path,
      libraryPath: _fixture('gesture_library.json').path,
    );
    when(() => brain.gestureLibrary).thenReturn(library);
    when(() => machine.state).thenReturn(Standing(sub));
    when(() => machine.groundedPose).thenReturn(GesturePose.lying);
    when(() => machine.profileSwitchInProgress).thenReturn(false);
    when(() => machine.isHandlingEvent).thenReturn(false);
    when(() => machine.isClosed).thenReturn(false);
    when(() => machine.commandVersion).thenReturn(0);
    when(() => machine.add(any())).thenReturn(null);
    when(() => call.remoteAddress).thenReturn(InternetAddress.loopbackIPv4);
    when(() => call.clientCertificate).thenReturn(null);
    when(() => call.isCanceled).thenReturn(false);
    when(() => call.isTimedOut).thenReturn(false);
  });

  tearDown(() async {
    await sub.cancel();
  });

  UnifiedCmsServer server({CmsMode mode = CmsMode.simulation}) =>
      UnifiedCmsServer(brain: brain, m: machine, mode: mode);

  test(
    'ListGestures returns the catalog fields and not posture RPCs',
    () async {
      final listed = await server().listGestures(call, proto.Empty());
      expect(listed.gestures.map((g) => g.name).toList(), [
        'nod_yes',
        'step_back',
        'wake_stand',
        'stand_up',
      ]);
      final nod = listed.gestures.first;
      expect(nod.description, '点头同意');
      expect(nod.durationMs, 60);
      expect(listed.gestures.map((g) => g.name), isNot(contains('bow')));
      expect(listed.gestures.map((g) => g.name), isNot(contains('StandUp')));
      expect(listed.gestures.map((g) => g.name), isNot(contains('SitDown')));
    },
  );

  test('PlayGesture by name dispatches that clip', () async {
    await server().playGesture(call, proto.GestureRequest(name: 'nod_yes'));
    verify(() => machine.add(const A.gesture('nod_yes'))).called(1);
    verifyNever(() => machine.add(const A.standUp()));
    verifyNever(() => machine.add(const A.gesture('wake_stand')));
    verifyNever(() => machine.add(const A.gesture('stand_up')));
  });

  test(
    'standing-start gesture from grounded still requests that clip',
    () async {
      when(() => machine.state).thenReturn(Grounded(sub));
      await server().playGesture(call, proto.GestureRequest(name: 'nod_yes'));
      verify(() => machine.add(const A.gesture('nod_yes'))).called(1);
      verifyNever(() => machine.add(const A.standUp()));
      verifyNever(() => machine.add(const A.gesture('wake_stand')));
    },
  );

  test('unknown, walking, and in-progress gestures are rejected', () async {
    final cms = server();
    await expectLater(
      cms.playGesture(call, proto.GestureRequest(name: 'missing')),
      throwsA(
        isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.notFound)
            .having((e) => e.message, 'message', contains('Unknown gesture')),
      ),
    );

    when(() => machine.state).thenReturn(Walking(sub));
    await expectLater(
      cms.playGesture(call, proto.GestureRequest(name: 'nod_yes')),
      throwsA(
        isA<GrpcError>().having(
          (e) => e.message,
          'message',
          contains('Robot is walking'),
        ),
      ),
    );

    when(
      () => machine.state,
    ).thenReturn(Transitioning(const Command.gesture('nod_yes'), sub, null));
    await expectLater(
      cms.playGesture(call, proto.GestureRequest(name: 'step_back')),
      throwsA(
        isA<GrpcError>().having(
          (e) => e.message,
          'message',
          contains('A gesture is already playing'),
        ),
      ),
    );
    verifyNever(() => machine.add(any()));
  });

  test('pose mismatch and profile switch are rejected with a reason', () async {
    when(() => machine.state).thenReturn(Grounded(sub));
    when(() => machine.groundedPose).thenReturn(GesturePose.lying);
    await expectLater(
      server().playGesture(call, proto.GestureRequest(name: 'stand_up')),
      throwsA(
        isA<GrpcError>().having(
          (e) => e.message,
          'message',
          contains('requires sitting'),
        ),
      ),
    );

    when(
      () => machine.state,
    ).thenReturn(Transitioning(const Command.gesture('nod_yes'), sub, null));
    final cms = server()
      ..profileManager = ProfileManager(
        profiles: {'mini': _profile('mini')},
        brain: brain,
        initial: 'mini',
      );
    await expectLater(
      cms.switchProfile(call, proto.ProfileRequest(name: 'mini')),
      throwsA(
        isA<GrpcError>().having(
          (e) => e.message,
          'message',
          contains('Cannot switch profile while a gesture is playing'),
        ),
      ),
    );

    when(() => machine.state).thenReturn(
      Transitioning(const Command.standUp(), sub, const A.gesture('nod_yes')),
    );
    await expectLater(
      cms.switchProfile(call, proto.ProfileRequest(name: 'mini')),
      throwsA(
        isA<GrpcError>().having(
          (e) => e.message,
          'message',
          contains('Cannot switch profile while a gesture is playing'),
        ),
      ),
    );
  });

  test(
    'disabled motors, faults, recovery, and offline joints reject playback',
    () async {
      final disabled = server(mode: CmsMode.hardware)
        ..motorOutputEnabledProvider = () => false;
      await expectLater(
        disabled.playGesture(call, proto.GestureRequest(name: 'nod_yes')),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.message,
            'message',
            contains('Motors are disabled'),
          ),
        ),
      );

      final faulted = server()..criticalMotorFaultProvider = () => true;
      await expectLater(
        faulted.playGesture(call, proto.GestureRequest(name: 'nod_yes')),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.message,
            'message',
            contains('Critical motor fault'),
          ),
        ),
      );

      final recovering = server()..recovery = _selectedRecovery();
      await expectLater(
        recovering.playGesture(call, proto.GestureRequest(name: 'nod_yes')),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.message,
            'message',
            contains('Exit recovery'),
          ),
        ),
      );

      final joint = _Joint();
      when(() => joint.isOnline(any())).thenReturn(false);
      final offline = server(mode: CmsMode.hardware)
        ..motorOutputEnabledProvider = () => true;
      offline.joint = joint;
      await expectLater(
        offline.playGesture(call, proto.GestureRequest(name: 'nod_yes')),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.message,
            'message',
            contains('offline joints'),
          ),
        ),
      );
      verifyNever(() => machine.add(any()));
    },
  );
}

File _fixture(String name) {
  final candidates = <String>[
    'thunder_brain/test/fixtures/$name',
    '../thunder_brain/test/fixtures/$name',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  throw StateError('Missing gesture fixture $name');
}

RobotProfile _profile(String name) {
  final zeros = JointsMatrix.zero();
  return RobotProfile(
    name: name,
    description: '$name profile',
    modelPath: '$name.onnx',
    standingPose: zeros,
    sittingPose: zeros,
    inferKp: zeros,
    inferKd: zeros,
    standUpKp: zeros,
    standUpKd: zeros,
    sitDownKp: zeros,
    sitDownKd: zeros,
  );
}

NormalRecoveryRuntime _selectedRecovery() {
  final runtime = NormalRecoveryRuntime(
    inference: _Inference(),
    sample: () => RecoverySample(
      angular: const [0, 0, 0],
      gravity: const [0, 0, -1],
      q: List<double>.filled(16, 0),
      dq: List<double>.filled(16, 0),
      ageMs: 0,
      healthy: true,
    ),
    canEnter: () => true,
    healthy: () => true,
    enabled: () => false,
    enableHardware: (_) async {},
    disableHardware: () async => true,
    sendHardware: (_) {},
    restoreNormalGains: () {},
    nowUs: () => 0,
    verified: true,
    lower: List<double>.filled(16, -4),
    upper: List<double>.filled(16, 4),
  );
  runtime.enter('operator', 'entry');
  return runtime;
}
