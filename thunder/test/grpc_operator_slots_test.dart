import 'dart:async';
import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

class MockBrain extends Mock implements Brain {}

class MockM extends Mock implements M {}

class MockCall extends Mock implements ServiceCall {}

class MockArbiter extends Mock implements ControlArbiter {}

RobotProfile profile(String name, double walkKp) => RobotProfile(
  name: name,
  description: name,
  modelPath: 'never-open-$name.onnx',
  standingPose: JointsMatrix.zero(),
  sittingPose: JointsMatrix.zero(),
  inferKp: JointsMatrix.fromList(List.filled(16, walkKp)),
  inferKd: JointsMatrix.zero(),
  standUpKp: JointsMatrix.zero(),
  standUpKd: JointsMatrix.zero(),
  sitDownKp: JointsMatrix.zero(),
  sitDownKd: JointsMatrix.zero(),
);

void main() {
  late MockBrain brain;
  late MockM m;
  late MockCall call;
  late UnifiedCmsServer server;
  late ProfileManager manager;
  late GainManager gains;
  late S state;
  late bool busy;
  late StreamSubscription<History> sub;
  late List<String?> prepared;
  String? block;
  var epoch = 0;
  Future<void>? pause;
  var handling = false;
  ControlSource? owner;
  var failPrepared = false;
  void Function()? afterBrainCommit;

  setUpAll(() {
    registerFallbackValue(JointsMatrix.zero());
    registerFallbackValue(
      StandardObservationBuilder(standingPose: JointsMatrix.zero()),
    );
    registerFallbackValue(GestureLibrary(standingPose: JointsMatrix.zero()));
    registerFallbackValue(const A.init());
  });
  setUp(() {
    brain = MockBrain();
    m = MockM();
    call = MockCall();
    sub = const Stream<History>.empty().listen((_) {});
    state = Grounded(sub);
    busy = false;
    block = null;
    epoch = 0;
    handling = false;
    pause = null;
    prepared = [];
    owner = null;
    failPrepared = false;
    afterBrainCommit = null;
    when(() => m.state).thenAnswer((_) => state);
    when(() => m.isHandlingEvent).thenAnswer((_) => handling);
    when(() => m.isClosed).thenReturn(false);
    when(() => m.commandVersion).thenReturn(0);
    when(() => call.remoteAddress).thenReturn(InternetAddress.loopbackIPv4);
    when(() => call.clientCertificate).thenReturn(null);
    when(() => call.isCanceled).thenReturn(false);
    when(() => call.isTimedOut).thenReturn(false);
    when(() => m.profileSwitchInProgress).thenAnswer((_) => busy);
    when(() => m.profileSwitchInProgress = any()).thenAnswer((i) {
      return busy = i.positionalArguments[0] as bool;
    });
    when(() => brain.gestureLibrary = any()).thenReturn(null);
    when(
      () => brain.switchProfile(
        observationBuilder: any(named: 'observationBuilder'),
        standingPose: any(named: 'standingPose'),
        sittingPose: any(named: 'sittingPose'),
        modelPath: any(named: 'modelPath'),
        standUpCounts: any(named: 'standUpCounts'),
        sitDownCounts: any(named: 'sitDownCounts'),
        forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
        canCommit: any(named: 'canCommit'),
        preparedProfile: any(named: 'preparedProfile'),
      ),
    ).thenAnswer((i) async {
      prepared.add(i.namedArguments[#preparedProfile] as String?);
      if (failPrepared && prepared.last == 'cts') {
        throw StateError('not preloaded');
      }
      await pause;
      final guard = i.namedArguments[#canCommit] as bool Function()?;
      if (guard != null && !guard()) {
        throw StateError('cancelled before commit');
      }
      afterBrainCommit?.call();
    });
    final flat = profile('w5', 80);
    gains = GainManager(
      inferKp: flat.inferKp,
      inferKd: flat.inferKd,
      standUpKp: flat.standUpKp,
      standUpKd: flat.standUpKd,
      sitDownKp: flat.sitDownKp,
      sitDownKd: flat.sitDownKd,
    );
    manager = ProfileManager(
      profiles: {
        'w5': flat,
        'cts': profile('cts', 90),
        'history': profile('history', 100),
      },
      brain: brain,
      gains: gains,
      initial: 'w5',
      operatorSlots: OperatorModeSlots.fromJson({
        'flat': 'w5',
        'stairs': 'cts',
      }),
    );
    final arbiter = MockArbiter();
    when(() => arbiter.owner).thenAnswer((_) => owner);
    when(
      () => arbiter.ownerStream,
    ).thenAnswer((_) => const Stream<ControlSource?>.empty());
    when(
      () => arbiter.contextVersion,
    ).thenReturn((commands: 0, ownership: 0, safety: 0));
    server =
        UnifiedCmsServer(
            brain: brain,
            m: m,
            mode: CmsMode.hardware,
            arbiter: arbiter,
          )
          ..profileManager = manager
          ..criticalMotorFaultProvider = (() => block != null)
          ..externalProfileContextProvider = (() => epoch);
  });
  tearDown(() async {
    await server.dispose();
    await sub.cancel();
  });

  Future<proto.ProfileInfo> switchTo(String name) =>
      server.switchProfile(call, proto.ProfileRequest(name: name));
  Matcher rejected(int code) =>
      throwsA(isA<GrpcError>().having((e) => e.code, 'code', code));

  test(
    'no gamepad: catalog exposes bound profile IDs only, in slot order',
    () async {
      final info = await server.getProfile(call, proto.Empty());
      expect(info.current, 'w5');
      expect(info.available, ['w5', 'cts']);
      expect(info.descriptions, ['flat: w5', 'stairs: cts']);
      expect(manager.controlDog, isNull);
    },
  );
  for (final standing in [false, true]) {
    test(
      'no gamepad: ${standing ? "Standing" : "Grounded"} switches cached slots without posture commands',
      () async {
        if (standing) state = Standing(sub);
        final original = state;
        expect((await switchTo('stairs')).current, 'cts');
        expect(gains.inferKp.values, everyElement(90));
        expect((await switchTo('w5')).current, 'w5');
        expect(prepared, ['cts', 'w5']);
        expect(identical(state, original), isTrue);
        verifyNever(() => m.add(any()));
        expect(busy, isFalse);
      },
    );
  }
  test('Walk, Zero and transitions rejected even for current slot', () async {
    for (final s in [
      Walking(sub),
      const Zero(),
      Transitioning(const StandUpCommand(), sub, null),
    ]) {
      state = s;
      await expectLater(
        switchTo('flat'),
        rejected(StatusCode.failedPrecondition),
      );
    }
    expect(prepared, isEmpty);
  });
  test('unassigned, unknown and historical profiles rejected', () async {
    for (final name in ['platform', 'bogus', 'history']) {
      await expectLater(switchTo(name), rejected(StatusCode.invalidArgument));
      expect(busy, isFalse);
    }
    expect(prepared, isEmpty);
  });
  test('current slot idempotent without loading model', () async {
    expect((await switchTo('flat')).current, 'w5');
    expect(prepared, isEmpty);
  });
  test(
    'local gRPC wire exposes catalog and switches without a gamepad',
    () async {
      final transport = Server.create(services: [server]);
      await transport.serve(address: InternetAddress.loopbackIPv4, port: 0);
      final channel = ClientChannel(
        '127.0.0.1',
        port: transport.port!,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      );
      try {
        final client = proto.RobotControlClient(channel);
        final catalog = await client.getProfile(proto.Empty());
        expect(catalog.available, ['w5', 'cts']);
        expect(
          (await client.switchProfile(
            proto.ProfileRequest(name: 'stairs'),
          )).current,
          'cts',
        );
        state = Standing(sub);
        expect(
          (await client.switchProfile(
            proto.ProfileRequest(name: 'flat'),
          )).current,
          'w5',
        );
        state = Walking(sub);
        await expectLater(
          client.switchProfile(proto.ProfileRequest(name: 'stairs')),
          rejected(StatusCode.failedPrecondition),
        );
      } finally {
        await channel.shutdown();
        await transport.shutdown();
      }
    },
  );
  test('original authorization and fault checks remain fail closed', () async {
    when(
      () => call.remoteAddress,
    ).thenReturn(InternetAddress('192.168.66.202'));
    await expectLater(
      switchTo('stairs'),
      rejected(StatusCode.permissionDenied),
    );
    when(() => call.remoteAddress).thenReturn(InternetAddress.loopbackIPv4);
    block = 'motor fault';
    await expectLater(
      switchTo('stairs'),
      rejected(StatusCode.failedPrecondition),
    );
    expect(prepared, isEmpty);
  });
  test('concurrent requests rejected; lock always released', () async {
    final pending = Completer<void>();
    pause = pending.future;
    final first = switchTo('stairs');
    expect(busy, isTrue);
    await expectLater(
      switchTo('flat'),
      rejected(StatusCode.failedPrecondition),
    );
    pending.complete();
    await first;
    expect(busy, isFalse);
  });
  test(
    'original lease guard refuses switching with an active motion lease',
    () async {
      final guarded =
          UnifiedCmsServer(brain: brain, m: m, mode: CmsMode.hardware)
            ..profileManager = manager
            ..motorOutputEnabledProvider = (() => true);
      try {
        state = Standing(sub);
        final lease = await guarded.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        expect(lease.accepted, isTrue);
        await expectLater(
          guarded.switchProfile(call, proto.ProfileRequest(name: 'stairs')),
          rejected(StatusCode.failedPrecondition),
        );
        expect(prepared, isEmpty);
      } finally {
        await guarded.dispose();
      }
    },
  );
  test(
    'original lease acquisition gate refuses the whole switching window',
    () async {
      state = Standing(sub);
      server.motorOutputEnabledProvider = () => true;
      final pending = Completer<void>();
      pause = pending.future;
      final switching = switchTo('stairs');
      final lease = await server.acquireControl(
        call,
        proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
      );
      expect(lease.accepted, isFalse);
      expect(
        lease.reason,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_FSM_NOT_READY,
      );
      pending.complete();
      await switching;
      expect(manager.currentName, 'cts');
    },
  );
  test(
    'disable remains available and cancels switch; enable is refused while switching',
    () async {
      final pending = Completer<void>();
      pause = pending.future;
      final first = switchTo('stairs');
      final assertion = expectLater(
        first,
        rejected(StatusCode.failedPrecondition),
      );
      await expectLater(
        server.enable(call, proto.Empty()),
        rejected(StatusCode.failedPrecondition),
      );
      await server.disable(call, proto.Empty());
      pending.complete();
      await assertion;
      expect(manager.currentName, 'w5');
      expect(busy, isFalse);
    },
  );
  test(
    'missing cache rejects without cold fallback or optimistic current profile',
    () async {
      failPrepared = true;
      await expectLater(
        switchTo('stairs'),
        rejected(StatusCode.failedPrecondition),
      );
      expect(manager.currentName, 'w5');
      expect(prepared, ['cts']);
      expect(busy, isFalse);
    },
  );
  test(
    'cancellation after Brain commit rolls back cached model and profile',
    () async {
      afterBrainCommit = () {
        ++epoch;
      };
      await expectLater(
        switchTo('stairs'),
        rejected(StatusCode.failedPrecondition),
      );
      expect(prepared, ['cts', 'w5']);
      expect(manager.currentName, 'w5');
      expect(gains.inferKp.values, everyElement(80));
      expect(busy, isFalse);
    },
  );
  test(
    'switch preserves hold gains; next Walk applies selected profile gains',
    () async {
      gains.applyCommand(const A.standUp());
      final held = gains.kp;
      state = Standing(sub);
      await switchTo('stairs');
      expect(identical(gains.kp, held), isTrue);
      gains.applyCommand(A.walk(Vector3.zero()));
      expect(gains.kp.values, everyElement(90));
      gains.applyCommand(const A.sitDown());
      expect(gains.kp.values, everyElement(0));
    },
  );
  for (final change in ['state', 'epoch', 'fault', 'handling', 'takeover']) {
    test(
      '$change change cancels before commit, retains old profile and PD',
      () async {
        final pending = Completer<void>();
        pause = pending.future;
        final first = switchTo('stairs');
        final assertion = expectLater(
          first,
          rejected(StatusCode.failedPrecondition),
        );
        switch (change) {
          case 'state':
            state = Grounded(sub);
          case 'epoch':
            ++epoch;
          case 'fault':
            block = 'fault';
          case 'handling':
            handling = true;
          case 'takeover':
            owner = ControlSource.yunzhuo;
        }
        pending.complete();
        await assertion;
        expect(manager.currentName, 'w5');
        expect(gains.inferKp.values, everyElement(80));
        expect(busy, isFalse);
      },
    );
  }
  test(
    'bootstrap retains the newer gRPC-only profile wiring and runtime guard',
    () {
      final root = File('thunder/bin/thunder.dart').existsSync() ? '' : '../';
      final source = File('${root}thunder/bin/thunder.dart').readAsStringSync();
      expect(source, contains('final wiring = configureAppProfiles('));
      expect(source, contains('externalProfileContextProvider'));
      expect(source, contains('cmsService.profileManager = profileManager;'));
      expect(source, contains('profiles[profileManager!.currentName]!'));
    },
  );
}
