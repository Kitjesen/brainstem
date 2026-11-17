import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:thunder/thunder.dart';
import 'package:thunder/src/web_controller.dart';
import 'package:thunder/src/web_control_runtime.dart';
import 'package:thunder/src/web_zero_stability.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockBrain extends Mock implements Brain {}

class MockJoint extends Mock implements RealJoint {}

class MockImu extends Mock implements RealImu {}

class MockArbiter extends Mock implements ControlArbiter {}

class MockDog extends Mock implements RealControlDog {}

class MockProfiles extends Mock implements ProfileManager {}

class TestWebInput extends WebController {
  final directions = StreamController<Vector3>.broadcast(sync: true);
  final enables = StreamController<bool>.broadcast(sync: true);
  TestWebInput()
    : super(
        token: 't' * 32,
        assetsPath: '.',
        status: () => {},
        selectSlot: (_) async {},
        zeroAll: () async => {},
      );
  @override
  Stream<Vector3> get direction => directions.stream;
  @override
  Stream<bool> get enabled => enables.stream;
  @override
  bool get hardStopActive => false;
  @override
  bool get inputHealthy => true;
  @override
  Future<void> close() async {
    await super.close();
    await directions.close();
    await enables.close();
  }
}

RobotProfile profile(String name) => RobotProfile(
  name: name,
  modelPath: '$name.onnx',
  standingPose: JointsMatrix.zero(),
  sittingPose: JointsMatrix.zero(),
  inferKp: JointsMatrix.fromList(List.filled(16, 80)),
  inferKd: JointsMatrix.fromList(List.filled(16, 6.93)),
  standUpKp: JointsMatrix.fromList(List.filled(16, 200)),
  standUpKd: JointsMatrix.fromList(List.filled(16, 8)),
  sitDownKp: JointsMatrix.fromList(List.filled(16, 200)),
  sitDownKd: JointsMatrix.fromList(List.filled(16, 8)),
);

RSStateReport report({
  double position = 0.2,
  double velocity = 0,
  RSStatus status = RSStatus.reset,
  int errors = 0,
}) => RSStateReport(
  hostId: 0,
  canId: 1,
  status: status,
  position: position,
  velocity: velocity,
  torque: 0,
  temperature: 25,
  errors: RSErrors1(errors),
);

void main() {
  late MockBrain brain;
  late MockJoint joint;
  late MockImu imu;
  late MockArbiter arbiter;
  late MockDog dog;
  late MockProfiles pm;
  late MotorEnableInterlock interlock;
  late List<RSStateReport> reports;
  late List<DateTime?> stamps;
  late WebControlRuntime runtime;
  late StreamController<(int, RSStateReport)> reportEvents;
  late DateTime zeroClock;
  var outputEnabled = false;
  var active = 'w5';
  final slots = OperatorModeSlots.fromJson({'flat': 'w5', 'stairs': 'v39'});
  final profiles = {'w5': profile('w5'), 'v39': profile('v39')};

  void publishReports() {
    zeroClock = zeroClock.add(const Duration(milliseconds: 5));
    stamps = List.filled(16, DateTime.now());
    for (var bus = 0; bus < 16; bus++) {
      final id = bus % 4 < 3 ? bus ~/ 4 * 3 + bus % 4 : 12 + bus ~/ 4;
      reportEvents.add((bus, reports[id]));
    }
  }

  Future<void> settleZero() async {
    for (var i = 0; i < 6; i++) {
      publishReports();
    }
  }

  setUpAll(() {
    registerFallbackValue(const A.init());
    registerFallbackValue(ControlSource.yunzhuo);
    registerFallbackValue(JointsMatrix.zero());
  });

  setUp(() async {
    brain = MockBrain();
    joint = MockJoint();
    reportEvents = StreamController<(int, RSStateReport)>.broadcast(sync: true);
    when(() => joint.reportStream).thenAnswer((_) => reportEvents.stream);
    when(() => joint.canZeroWriteImmediately).thenReturn(true);
    addTearDown(reportEvents.close);
    imu = MockImu();
    arbiter = MockArbiter();
    dog = MockDog();
    pm = MockProfiles();
    interlock = MotorEnableInterlock()..permit();
    outputEnabled = false;
    active = 'w5';
    zeroClock = DateTime.utc(2026);
    reports = List.generate(16, (_) => report());
    stamps = List.filled(16, DateTime.now());
    when(
      () => joint.latestReport(any()),
    ).thenAnswer((i) => reports[i.positionalArguments.first as int]);
    when(
      () => joint.latestReportAt(any()),
    ).thenAnswer((i) => stamps[i.positionalArguments.first as int]);
    when(() => joint.setZero()).thenAnswer((_) async => true);
    when(() => brain.histories).thenReturn([]);
    when(() => imu.isStale).thenReturn(false);
    when(() => imu.gyroscope).thenReturn(Vector3.zero());
    when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
    when(
      () => arbiter.state,
    ).thenReturn(Grounded(const Stream<History>.empty().listen((_) {})));
    when(() => arbiter.isHandlingEvent).thenReturn(false);
    when(() => arbiter.profileSwitchInProgress).thenReturn(false);
    when(() => dog.canSwitchProfile).thenReturn(true);
    when(() => pm.currentName).thenAnswer((_) => active);
    runtime = WebControlRuntime(
      brain: brain,
      joint: joint,
      imu: imu,
      arbiter: arbiter,
      controlDog: dog,
      profileManager: pm,
      slots: slots,
      profiles: profiles,
      interlock: interlock,
      motorOutputEnabled: () => outputEnabled,
      allowMotorEnable: true,
      zeroTimeout: const Duration(milliseconds: 100),
      zeroPoll: const Duration(milliseconds: 5),
      zeroStableFor: const Duration(milliseconds: 10),
      zeroClock: () => zeroClock,
    );
    addTearDown(runtime.dispose);
    await settleZero();
  });

  void enabledReports() {
    outputEnabled = true;
    reports = List.generate(16, (_) => report(status: RSStatus.motor));
    stamps = List.filled(16, DateTime.now());
  }

  test('pending runtime is never ready, enabled or calibration-capable', () {
    final s = WebControlRuntime.pendingStatus();
    expect(s['ready'], false);
    expect(s['motor_enabled'], false);
    expect(s['hardware_state_unknown'], true);
    for (final key in ['can_enable', 'can_switch', 'can_zero']) {
      expect(s[key], false);
    }
  });

  test(
    'status uses actual motor feedback, profile bounds and policy order',
    () {
      outputEnabled = true; // Requested output is not feedback confirmation.
      var s = runtime.snapshot();
      expect(s['motor_enabled'], false);
      expect(s['can_zero'], false);
      enabledReports();
      when(() => brain.histories).thenReturn([
        History.zero().copyWith(command: Command.walk(Vector3(.2, -.3, .4))),
      ]);
      s = runtime.snapshot();
      expect(s['motor_enabled'], true);
      expect(
        s['command'],
        orderedEquals([
          closeTo(.2, 1e-6),
          closeTo(-.3, 1e-6),
          closeTo(.4, 1e-6),
        ]),
      );
      expect(s['limits'], {'vx': 1.5, 'vy': 1.0, 'yaw': 1.0});
      expect(s['minimums'], {'vx': 0.0, 'vy': .3, 'yaw': .4});
      expect(s['slots'], {'flat': 'w5', 'stairs': 'v39'});
      final motors = (s['motors'] as List).cast<Map<String, Object?>>();
      expect(motors.length, 16);
      expect(motors[3]['leg'], 'FL');
      expect(motors[3]['joint'], 'Hip');
      expect(motors[3]['status'], 2);
      expect(motors[12]['leg'], 'FR');
      expect(motors[12]['joint'], 'Foot');
      expect(motors[15]['leg'], 'RL');
      expect(jsonDecode(jsonEncode(s)), isA<Map<String, dynamic>>());
    },
  );

  test(
    'stale, partial, invalid or faulted feedback cannot permit enable/zero',
    () {
      stamps[15] = DateTime.now().subtract(const Duration(seconds: 1));
      expect(runtime.snapshot()['can_enable'], false);
      expect(runtime.snapshot()['can_zero'], false);
      expect(runtime.snapshot()['hardware_state_unknown'], true);
      stamps[15] = DateTime.now();
      reports[15] = report(status: RSStatus.motor);
      expect(runtime.snapshot()['can_enable'], false);
      expect(runtime.snapshot()['can_zero'], false);
      reports[15] = report(position: double.nan);
      expect(runtime.snapshot()['can_enable'], false);
      expect(() => jsonEncode(runtime.snapshot()), returnsNormally);
      reports[15] = report(errors: 1);
      expect(runtime.snapshot()['can_enable'], false);
      expect(runtime.snapshot()['can_zero'], false);
    },
  );

  test(
    'boot interlock and explicit motor enable environment remain required',
    () {
      interlock.block('boot hardware fault');
      expect(runtime.snapshot()['can_enable'], false);
      expect(runtime.snapshot()['block_reason'], 'boot hardware fault');
      interlock.permit();
      final blocked = WebControlRuntime(
        brain: brain,
        joint: joint,
        imu: imu,
        arbiter: arbiter,
        controlDog: dog,
        profileManager: pm,
        slots: slots,
        profiles: profiles,
        interlock: interlock,
        motorOutputEnabled: () => false,
        allowMotorEnable: false,
      );
      addTearDown(blocked.dispose);
      expect(blocked.snapshot()['can_enable'], false);
      expect(
        blocked.snapshot()['block_reason'],
        contains('THUNDER_ALLOW_MOTOR_ENABLE'),
      );
    },
  );

  test(
    'slot selection accepts only slots and awaits shared R2 request',
    () async {
      enabledReports();
      await expectLater(
        runtime.selectSlot('arbitrary-profile'),
        throwsArgumentError,
      );
      final pending = Completer<void>();
      when(() => dog.requestProfileSwitch()).thenAnswer((_) async {
        await pending.future;
        active = 'v39';
      });
      final switching = runtime.selectSlot('stairs');
      expect(runtime.snapshot()['busy'], true);
      expect(runtime.snapshot()['model_slot'], 'flat');
      pending.complete();
      await switching;
      expect(runtime.snapshot()['model_slot'], 'stairs');
      expect(runtime.snapshot()['busy'], false);
      verify(() => dog.requestProfileSwitch()).called(1);
      // A direct ProfileManager.switchTo would bypass the R2 state/generation gate.
      verifyNever(() => pm.toggle());
    },
  );

  test('web rejects a non-next three-slot selection before R2', () async {
    enabledReports();
    final threeSlots = OperatorModeSlots.fromJson({
      'flat': 'w5', 'stairs': 'v39', 'high_platform': 'platform',
    });
    final web = WebControlRuntime(
      brain: brain, joint: joint, imu: imu, arbiter: arbiter, controlDog: dog,
      profileManager: pm, slots: threeSlots,
      profiles: {...profiles, 'platform': profile('platform')},
      interlock: interlock, motorOutputEnabled: () => outputEnabled,
      allowMotorEnable: true,
    );
    addTearDown(web.dispose);
    await expectLater(web.selectSlot('high_platform'), throwsStateError);
    verifyNever(() => dog.requestProfileSwitch());
    expect(active, 'w5');
  });

  test('actual enabled feedback does not imply the output path is ready', () {
    enabledReports();
    outputEnabled = false;
    final state = runtime.snapshot();
    expect(state['motor_enabled'], true);
    expect(state['motor_output_enabled'], false);
    expect(state['can_zero'], false);
    when(() => imu.isStale).thenReturn(true);
    expect(runtime.snapshot()['can_enable'], false);
    expect(runtime.snapshot()['can_switch'], false);
  });

  test(
    'partial physical enable must not be reported as confirmed disabled',
    () {
      reports[0] = report(status: RSStatus.motor);
      final state = runtime.snapshot();
      expect(state['motor_enabled'], false);
      expect(state['hardware_state_unknown'], true);
      expect(state['can_enable'], false);
      expect(state['can_zero'], false);
    },
  );

  test(
    'motion/state R2 denial is not bypassed; failed commit is not optimistic',
    () async {
      enabledReports();
      when(() => dog.canSwitchProfile).thenReturn(false);
      await expectLater(runtime.selectSlot('stairs'), throwsStateError);
      verifyNever(() => dog.requestProfileSwitch());
      when(() => dog.canSwitchProfile).thenReturn(true);
      when(() => dog.requestProfileSwitch()).thenAnswer((_) async {});
      await expectLater(runtime.selectSlot('stairs'), throwsStateError);
      expect(runtime.snapshot()['model_slot'], 'flat');
      expect(runtime.snapshot()['busy'], false);
    },
  );

  test(
    'zero rejects output enabled, physical enable, motion and transitions',
    () async {
      outputEnabled = true;
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      outputEnabled = false;
      reports[4] = report(status: RSStatus.motor);
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      reports[4] = report(velocity: .2);
      await settleZero();
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      reports[4] = report();
      when(() => arbiter.isHandlingEvent).thenReturn(true);
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      when(() => arbiter.isHandlingEvent).thenReturn(false);
      when(
        () => arbiter.state,
      ).thenReturn(Standing(const Stream<History>.empty().listen((_) {})));
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      verifyNever(() => joint.setZero());
    },
  );

  test('zero dialog stays available while a new stability window fills', () {
    final waiting = WebControlRuntime(
      brain: brain,
      joint: joint,
      imu: imu,
      arbiter: arbiter,
      controlDog: dog,
      profileManager: pm,
      slots: slots,
      profiles: profiles,
      interlock: interlock,
      motorOutputEnabled: () => outputEnabled,
      allowMotorEnable: true,
    );
    addTearDown(waiting.dispose);
    final s = waiting.snapshot();
    expect(s['can_open_zero'], true);
    expect(s['can_zero'], false);
    expect(s['zero_block_reason'], contains('500ms'));
    reports[3] = report(errors: 1);
    expect(waiting.snapshot()['can_open_zero'], false);
    expect(waiting.snapshot()['zero_block_reason'], contains('FL Hip'));
    verifyNever(() => joint.setZero());
  });

  test('velocity noise does not toggle readiness or call calibration', () {
    for (var i = 0; i < 30; i++) {
      reports = List.generate(
        16,
        (_) => report(
          position: .2 + (i.isEven ? .0004 : -.0004),
          velocity: i.isEven ? .3 : -.3,
        ),
      );
      publishReports();
      final s = runtime.snapshot();
      expect(s['can_open_zero'], true);
      expect(s['can_zero'], true);
    }
    verifyNever(() => joint.setZero());
    verifyNever(() => joint.enable());
  });

  test(
    'final write gate rechecks feedback instead of trusting prior status',
    () async {
      expect(runtime.snapshot()['can_zero'], true);
      reports[15] = report(status: RSStatus.motor);
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      verifyNever(() => joint.setZero());
      reports[15] = report();
      expect(runtime.snapshot()['can_enable'], true);
    },
  );

  test('a closed report stream invalidates stationary evidence', () async {
    expect(runtime.snapshot()['can_zero'], true);
    await reportEvents.close();
    expect(runtime.snapshot()['can_zero'], false);
    verifyNever(() => joint.setZero());
  });

  test(
    'zero writes once and requires fresh stable post-write confirmation',
    () async {
      final pending = Completer<bool>();
      when(() => joint.setZero()).thenAnswer((_) => pending.future);
      final zero = runtime.zeroAll();
      expect(runtime.snapshot()['busy'], true);
      expect(runtime.snapshot()['can_enable'], false);
      expect(runtime.snapshot()['can_zero'], false);
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      pending.complete(true);
      final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
        reports = List.generate(16, (_) => report(position: .0002));
        publishReports();
      });
      addTearDown(timer.cancel);
      final result = await zero;
      expect(result['verified'], 16);
      expect(result['power_cycle_verified'], false);
      expect(result['positions'], everyElement(closeTo(0, .01)));
      expect(runtime.snapshot()['busy'], false);
      verify(() => joint.setZero()).called(1);
      verifyNever(() => joint.enable());
      verifyNever(() => joint.sendAction(any()));
    },
  );

  test(
    'old near-zero reports cannot verify calibration or trigger retries',
    () async {
      reports = List.generate(16, (_) => report(position: 0));
      await expectLater(runtime.zeroAll(), throwsA(isA<TimeoutException>()));
      verify(() => joint.setZero()).called(1);
      expect(runtime.snapshot()['busy'], false);
    },
  );

  test(
    'a single nonzero post-write motor times out; fault aborts immediately',
    () async {
      final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
        reports = List.generate(
          16,
          (id) => report(position: id == 15 ? .1 : 0),
        );
        publishReports();
      });
      addTearDown(timer.cancel);
      await expectLater(runtime.zeroAll(), throwsA(isA<TimeoutException>()));
      timer.cancel();
      reports = List.generate(16, (_) => report(position: 0));
      await settleZero();
      when(() => joint.setZero()).thenAnswer((_) async {
        reports[3] = report(status: RSStatus.motor);
        return true;
      });
      await expectLater(runtime.zeroAll(), throwsStateError);
      verifyNever(() => joint.enable());
      verifyNever(() => joint.disable());
    },
  );

  test(
    'one fresh near-zero frame is not a stable post-write verification',
    () async {
      final zero = runtime.zeroAll();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      reports = List.generate(16, (_) => report(position: 0));
      publishReports();
      await expectLater(zero, throwsA(isA<TimeoutException>()));
      verify(() => joint.setZero()).called(1);
    },
  );

  test(
    'rejected zero write returns failure without retrying or enabling',
    () async {
      when(() => joint.setZero()).thenAnswer((_) async => false);
      await expectLater(runtime.zeroAll(), throwsStateError);
      expect(runtime.snapshot()['busy'], false);
      verify(() => joint.setZero()).called(1);
      verifyNever(() => joint.enable());
    },
  );

  test(
    'busy CAN is a pre-write refusal, never a calibration attempt',
    () async {
      when(() => joint.canZeroWriteImmediately).thenReturn(false);
      expect(runtime.snapshot()['can_open_zero'], true);
      expect(runtime.snapshot()['can_zero'], false);
      await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
      verifyNever(() => joint.setZero());
    },
  );

  test('dispose during a pending write cannot produce late success', () async {
    final write = Completer<bool>();
    when(() => joint.setZero()).thenAnswer((_) => write.future);
    final zero = runtime.zeroAll();
    runtime.dispose();
    write.complete(true);
    await expectLater(zero, throwsStateError);
    verify(() => joint.setZero()).called(1);
    verifyNever(() => joint.enable());
  });

  test('dispose during verification fails without retries', () async {
    final zero = runtime.zeroAll();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    runtime.dispose();
    await expectLater(zero, throwsStateError);
    verify(() => joint.setZero()).called(1);
    verifyNever(() => joint.enable());
  });

  test('closed runtime cannot calibrate or select a model', () async {
    runtime.dispose();
    expect(runtime.snapshot()['ready'], false);
    await expectLater(runtime.zeroAll(), throwsA(isA<ZeroNotStarted>()));
    await expectLater(runtime.selectSlot('stairs'), throwsStateError);
    verifyNever(() => joint.setZero());
  });

  group('opt-in startup configuration', () {
    test('unset/false does not read tokens or change nonweb gRPC binding', () {
      expect(WebControlConfig.fromEnvironment({}), isNull);
      expect(
        WebControlConfig.fromEnvironment({
          'THUNDER_WEB_CONTROL_ENABLED': 'false',
        }),
        isNull,
      );
      expect(
        WebControlConfig.grpcAddress(webEnabled: false),
        InternetAddress.anyIPv4,
      );
      expect(
        WebControlConfig.grpcAddress(webEnabled: true),
        InternetAddress.loopbackIPv4,
      );
      expect(
        () => WebControlConfig.fromEnvironment({
          'THUNDER_WEB_CONTROL_ENABLED': 'true',
        }),
        throwsStateError,
      );
    });

    test('validates private token and assets before opening devices', () async {
      final temp = Directory.systemTemp.createTempSync('thunder-web-config-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final token = File('${temp.path}/token')..writeAsStringSync('t' * 32);
      if (!Platform.isWindows) await Process.run('chmod', ['600', token.path]);
      final env = {
        'THUNDER_WEB_CONTROL_ENABLED': 'true',
        'THUNDER_WEB_TOKEN_FILE': token.path,
        'THUNDER_WEB_ASSETS': temp.path,
      };
      expect(() => WebControlConfig.fromEnvironment(env), throwsStateError);
      for (final name in ['index.html', 'app.js', 'styles.css']) {
        File('${temp.path}/$name').writeAsStringSync('');
      }
      final config = WebControlConfig.fromEnvironment(env)!;
      expect(config.port, 8088);
      expect(config.host, '0.0.0.0');
      expect(config.token, 't' * 32);
      expect(
        () =>
            WebControlConfig.fromEnvironment({...env, 'THUNDER_WEB_PORT': '0'}),
        throwsStateError,
      );
      token.writeAsStringSync('short');
      expect(() => WebControlConfig.fromEnvironment(env), throwsStateError);
      if (!Platform.isWindows) {
        token.writeAsStringSync('t' * 32);
        await Process.run('chmod', ['644', token.path]);
        expect(() => WebControlConfig.fromEnvironment(env), throwsStateError);
      }
    });

    test(
      'main web branch feeds the normal RealControlDog/ProfileManager path',
      () {
        final file = File('bin/thunder.dart').existsSync()
            ? File('bin/thunder.dart')
            : File('thunder/bin/thunder.dart');
        final source = file.readAsStringSync();
        final webAssignment = source.indexOf('controller = webController;');
        // Shared startup path after the web/local controller choice, not the
        // local-open branch that only logs which device opened.
        final sharedWiring = source.indexOf(
          'if (controller != null &&',
          webAssignment,
        );
        final sharedEnd = source.indexOf('} else {', sharedWiring);
        expect(webAssignment, greaterThan(0));
        expect(sharedWiring, greaterThan(webAssignment));
        expect(sharedEnd, greaterThan(sharedWiring));
        final wiring = source.substring(sharedWiring, sharedEnd);
        expect(wiring, contains('controlDog = RealControlDog('));
        expect(wiring, contains('controller: controller,'));
        expect(wiring, contains('inferKp: defaultProfile.inferKp,'));
        expect(wiring, contains('standUpKp: defaultProfile.standUpKp,'));
        expect(wiring, contains('sitDownKp: defaultProfile.sitDownKp,'));
        expect(wiring, contains('profileManager = ProfileManager('));
        expect(wiring, contains('operatorSlots: operatorSlots,'));
        final runtime = source.indexOf(
          'webRuntime = WebControlRuntime(',
          sharedEnd,
        );
        final runtimeEnd = source.indexOf(');', runtime);
        expect(runtime, greaterThan(sharedEnd));
        expect(runtimeEnd, greaterThan(runtime));
        final runtimeBlock = source.substring(runtime, runtimeEnd);
        expect(runtimeBlock, contains('controlDog: controlDog!'));
        expect(runtimeBlock, contains('profileManager: profileManager!'));
        expect(
          source.indexOf('WebControlConfig.fromEnvironment'),
          lessThan(source.indexOf('createHardwareJoint()')),
        );
        expect(source, contains('_startGrpc(cmsService, _cfg)'));
      },
    );
  });

  test(
    'virtual web Gamepad uses RealControlDog gains, direct input and policy wheel release',
    () async {
      final web = TestWebInput();
      addTearDown(web.close);
      final stateEvents = StreamController<S>.broadcast(sync: true);
      addTearDown(stateEvents.close);
      when(() => arbiter.stateStream).thenAnswer((_) => stateEvents.stream);
      when(() => arbiter.command(any(), any())).thenReturn(true);
      when(() => joint.enable()).thenAnswer((_) async {});
      final walking = Walking(const Stream<History>.empty().listen((_) {}));
      final p = profiles['w5']!;
      final actual = RealControlDog(
        brain: brain,
        joint: joint,
        imu: imu,
        arbiter: arbiter,
        controller: web,
        inferKp: p.inferKp,
        inferKd: p.inferKd,
        standUpKp: p.standUpKp,
        standUpKd: p.standUpKd,
        sitDownKp: p.sitDownKp,
        sitDownKd: p.sitDownKd,
      );
      addTearDown(actual.dispose);
      stateEvents.add(
        Transitioning(
          const Command.standUp(),
          const Stream<History>.empty().listen((_) {}),
          null,
        ),
      );
      verify(() => joint.kpExt = p.standUpKp).called(1);
      verify(() => joint.kdExt = p.standUpKd).called(1);
      stateEvents.add(
        Transitioning(
          const Command.sitDown(),
          const Stream<History>.empty().listen((_) {}),
          null,
        ),
      );
      verify(() => joint.kpExt = p.sitDownKp).called(1);
      stateEvents.add(walking);
      verify(() => joint.kpExt = p.inferKp).called(1);
      when(() => arbiter.state).thenReturn(walking);
      expect(actual.canSwitchProfile, false);
      await expectLater(actual.requestProfileSwitch(), throwsStateError);
      web.enables.add(true);
      await Future<void>.delayed(Duration.zero);
      web.directions.add(Vector3(.5, 0, 0));
      var sent =
          verify(
                () => arbiter.command(captureAny(), ControlSource.yunzhuo),
              ).captured.single
              as CmdWalk;
      expect(
        sent.direction.x,
        greaterThan(0),
      ); // No first-frame acceleration delay.
      web.directions.add(Vector3.zero());
      sent =
          verify(
                () => arbiter.command(captureAny(), ControlSource.yunzhuo),
              ).captured.single
              as CmdWalk;
      expect(sent.direction.length2, 0);
      expect(
        sent.forceWheelStop,
        false,
      ); // Ordinary release retains the policy wheel output.
      when(
        () => arbiter.state,
      ).thenReturn(Grounded(const Stream<History>.empty().listen((_) {})));
      var switched = false;
      actual.onProfileSwitch = () async {
        switched = true;
      };
      await actual.requestProfileSwitch();
      expect(switched, true);
      verify(() => arbiter.profileSwitchInProgress = true).called(1);
      verify(() => arbiter.profileSwitchInProgress = false).called(1);
    },
  );
}
