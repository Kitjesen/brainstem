import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

// ─── Mock 类 ──────────────────────────────────────────────────────────

class _MockBrain extends Mock implements Brain {}

class _MockM extends Mock implements M {}

class _MockServiceCall extends Mock implements ServiceCall {}

class _MockMotorService extends Mock implements MotorService {}

class _MockRealJoint extends Mock implements RealJoint {}

// ─── 测试工具函数 ──────────────────────────────────────────────────────

final _zeros16 = JointsMatrix.fromList(List.filled(16, 0.0));

RobotProfile _profile(String name) => RobotProfile(
  name: name,
  description: '$name 策略说明',
  modelPath: '$name.onnx',
  standingPose: _zeros16,
  sittingPose: _zeros16,
  inferKp: _zeros16,
  inferKd: _zeros16,
  standUpKp: _zeros16,
  standUpKd: _zeros16,
  sitDownKp: _zeros16,
  sitDownKd: _zeros16,
);
RobotProfile _boundedProfile(
  String name, {
  double minBodyHeightCommand = 0.20,
  double maxBodyHeightCommand = 0.54,
  (double, double, double) velocityCommandMin = (-3.0, -3.0, -3.0),
  (double, double, double) velocityCommandMax = (3.0, 3.0, 3.0),
}) => RobotProfile(
  name: name,
  modelPath: '$name.onnx',
  standingPose: _zeros16,
  sittingPose: _zeros16,
  inferKp: _zeros16,
  inferKd: _zeros16,
  standUpKp: _zeros16,
  standUpKd: _zeros16,
  sitDownKp: _zeros16,
  sitDownKd: _zeros16,
  minBodyHeightCommand: minBodyHeightCommand,
  maxBodyHeightCommand: maxBodyHeightCommand,
  velocityCommandMin: velocityCommandMin,
  velocityCommandMax: velocityCommandMax,
);

/// 创建仿真模式服务器（无 arbiter，无 simInjector）。
UnifiedCmsServer _simServer(_MockBrain brain, _MockM m) =>
    UnifiedCmsServer(brain: brain, m: m, mode: CmsMode.simulation);

void main() {
  late _MockBrain brain;
  late _MockM m;
  late _MockServiceCall call;

  setUpAll(() {
    registerFallbackValue(const A.init());
    registerFallbackValue(JointsMatrix.zero());
    registerFallbackValue(GestureLibrary(standingPose: JointsMatrix.zero()));
    registerFallbackValue(
      StandardObservationBuilder(standingPose: JointsMatrix.zero()),
    );
  });

  setUp(() {
    brain = _MockBrain();
    m = _MockM();
    call = _MockServiceCall();

    // historyStream は late final で遅延初期化 — streaming RPC を呼ばない限り不要。
    // isModelLoaded のデフォルト = true（必要なテストで上書き）。
    when(() => brain.isModelLoaded).thenReturn(true);
    when(() => brain.standingPose).thenReturn(_zeros16);
    when(() => m.add(any())).thenReturn(null);
    when(() => m.state).thenReturn(const Zero());
  });

  // ─── walk 入力バリデーション ──────────────────────────────────────────

  group('walk — 输入验证', () {
    test('NaN 方向向量 → 静默忽略', () async {
      final server = _simServer(brain, m);
      final result = await server.walk(
        call,
        proto.Vector3(x: double.nan, y: 0, z: 0),
      );
      expect(result, isA<proto.Empty>());
    });

    test('Inf 方向向量 → 静默忽略', () async {
      final server = _simServer(brain, m);
      final result = await server.walk(
        call,
        proto.Vector3(x: double.infinity, y: 0, z: 0),
      );
      expect(result, isA<proto.Empty>());
    });

    test('幅值超过 3.0 → clamp 后执行', () async {
      final server = _simServer(brain, m);
      final result = await server.walk(call, proto.Vector3(x: 3.1, y: 0, z: 0));
      expect(result, isA<proto.Empty>());
    });

    test('合法方向 → 调用 m.add()', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));

      final server = _simServer(brain, m);
      await server.walk(call, proto.Vector3(x: 0.5, y: 0, z: 0));
      verify(() => m.add(any())).called(1);

      await sub.cancel();
      await historyCtrl.close();
    });

    test('profile clamp still preserves the legacy magnitude limit', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.simulation,
        initialProfile: _profile('standard'),
      );

      await server.walk(call, proto.Vector3(x: 3, y: 3, z: 3));

      final action =
          verify(() => m.add(captureAny())).captured.single as CmdWalk;
      expect(action.direction.length, closeTo(3.0, 1e-6));
      expect(action.direction.x, closeTo(1.7320508075688772, 1e-6));
      expect(action.direction.y, closeTo(1.7320508075688772, 1e-6));
      expect(action.direction.z, closeTo(1.7320508075688772, 1e-6));

      await sub.cancel();
      await historyCtrl.close();
    });
  });

  // ─── tick モードガード ────────────────────────────────────────────────

  group('tick — 模式守卫', () {
    test('hardware 模式下调用 tick → GrpcError.failedPrecondition', () async {
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
      );
      await expectLater(
        server.tick(call, proto.Empty()),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.failedPrecondition,
          ),
        ),
      );
    });

    test('模型未加载时调用 tick → GrpcError.failedPrecondition', () async {
      when(() => brain.isModelLoaded).thenReturn(false);
      final server = _simServer(brain, m);
      await expectLater(
        server.tick(call, proto.Empty()),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.failedPrecondition,
          ),
        ),
      );
    });
  });

  // ─── step モードガード ────────────────────────────────────────────────

  group('motor enable safety', () {
    test(
      'hardware mode rejects enable when motor service is unavailable',
      () async {
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
        );

        await expectLater(
          server.enable(call, proto.Empty()),
          throwsA(
            isA<GrpcError>().having(
              (e) => e.code,
              'code',
              StatusCode.failedPrecondition,
            ),
          ),
        );
      },
    );

    test(
      'hardware mode rejects unsafe joint preflight without enabling',
      () async {
        final motor = _MockMotorService();
        final joint = _MockRealJoint();
        when(() => motor.enable()).thenAnswer((_) async {});
        when(() => motor.disable()).thenAnswer((_) async {});
        when(
          () => joint.motorEnableBlockReason(),
        ).thenReturn('motor authorization is disabled');
        final enabledStates = <bool>[];
        final server =
            UnifiedCmsServer(
                brain: brain,
                m: m,
                mode: CmsMode.hardware,
                motor: motor,
              )
              ..joint = joint
              ..onMotorEnableChanged = enabledStates.add;

        await expectLater(
          server.enable(call, proto.Empty()),
          throwsA(
            isA<GrpcError>().having(
              (e) => e.code,
              'code',
              StatusCode.failedPrecondition,
            ),
          ),
        );
        verifyNever(() => motor.enable());
        verify(() => motor.disable()).called(1);
        expect(enabledStates, [false]);
      },
    );

    test(
      'callback becomes true only after a successful hardware enable',
      () async {
        final motor = _MockMotorService();
        final joint = _MockRealJoint();
        when(() => motor.enable()).thenAnswer((_) async {});
        when(() => joint.motorEnableBlockReason()).thenReturn(null);
        final enabledStates = <bool>[];
        final server =
            UnifiedCmsServer(
                brain: brain,
                m: m,
                mode: CmsMode.hardware,
                motor: motor,
              )
              ..joint = joint
              ..onMotorEnableChanged = enabledStates.add;

        await server.enable(call, proto.Empty());

        verify(() => motor.enable()).called(1);
        expect(enabledStates, [true]);
      },
    );

    test('failed hardware enable never reports enabled', () async {
      final motor = _MockMotorService();
      final joint = _MockRealJoint();
      when(() => motor.enable()).thenThrow(StateError('CAN write failed'));
      when(() => motor.disable()).thenAnswer((_) async {});
      when(() => joint.motorEnableBlockReason()).thenReturn(null);
      final enabledStates = <bool>[];
      final server =
          UnifiedCmsServer(
              brain: brain,
              m: m,
              mode: CmsMode.hardware,
              motor: motor,
            )
            ..joint = joint
            ..onMotorEnableChanged = enabledStates.add;

      await expectLater(server.enable(call, proto.Empty()), throwsStateError);

      verify(() => motor.disable()).called(1);
      expect(enabledStates, [false]);
    });

    test('failed hardware disable still stops policy output', () async {
      final motor = _MockMotorService();
      when(() => motor.disable()).thenThrow(StateError('CAN write failed'));
      final enabledStates = <bool>[];
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        motor: motor,
      )..onMotorEnableChanged = enabledStates.add;

      await expectLater(server.disable(call, proto.Empty()), throwsStateError);

      expect(enabledStates, [false]);
    });
  });

  group('step — 模式守卫', () {
    test('无 simInjector 时调用 step → GrpcError.failedPrecondition', () async {
      // simInjector 为 null（_simServer 不传入 simInjector）
      final server = _simServer(brain, m);
      await expectLater(
        server.step(call, proto.SimState()),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.failedPrecondition,
          ),
        ),
      );
    });
  });

  // ─── getProfile ──────────────────────────────────────────────────────

  group('getProfile', () {
    test('profileManager 未配置 → GrpcError.unimplemented', () async {
      final server = _simServer(brain, m);
      // profileManager 默认为 null
      await expectLater(
        server.getProfile(call, proto.Empty()),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.unimplemented,
          ),
        ),
      );
    });

    test('已配置 profileManager → 返回正确的 ProfileInfo', () async {
      final server = _simServer(brain, m);
      server.profileManager = ProfileManager(
        profiles: {'mini': _profile('mini'), 'fast': _profile('fast')},
        brain: brain,
        initial: 'mini',
      );

      final info = await server.getProfile(call, proto.Empty());

      expect(info.current, 'mini');
      expect(info.available, containsAll(['mini', 'fast']));
      expect(info.currentDescription, 'mini 策略说明');
      expect(info.descriptions.length, 2);
    });
  });

  // ─── switchProfile ───────────────────────────────────────────────────

  group('switchProfile', () {
    test('profileManager 未配置 → GrpcError.unimplemented', () async {
      final server = _simServer(brain, m);
      await expectLater(
        server.switchProfile(call, proto.ProfileRequest(name: 'mini')),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.unimplemented,
          ),
        ),
      );
    });

    test('FSM 非 Grounded 状态 → GrpcError.failedPrecondition', () async {
      // m.state 默认返回 Zero()，不是 Grounded
      final server = _simServer(brain, m);
      server.profileManager = ProfileManager(
        profiles: {'mini': _profile('mini')},
        brain: brain,
        initial: 'mini',
      );
      await expectLater(
        server.switchProfile(call, proto.ProfileRequest(name: 'mini')),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.failedPrecondition,
          ),
        ),
      );
    });

    test('未知策略名称 → GrpcError.invalidArgument', () async {
      // 让 m.state 返回 Grounded — 需要一个 StreamSubscription<History>
      final ctrl = StreamController<History>();
      final sub = ctrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Grounded(sub));

      final server = _simServer(brain, m);
      server.profileManager = ProfileManager(
        profiles: {'mini': _profile('mini')},
        brain: brain,
        initial: 'mini',
      );

      await expectLater(
        server.switchProfile(call, proto.ProfileRequest(name: 'fast_walk')),
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.invalidArgument,
          ),
        ),
      );

      await sub.cancel();
      await ctrl.close();
    });
  });

  group('motion preconditions', () {
    test('Grounded walk → 静默忽略', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Grounded(sub));

      final server = _simServer(brain, m);
      final result = await server.walk(call, proto.Vector3(x: 0.5, y: 0, z: 0));
      expect(result, isA<proto.Empty>());

      await sub.cancel();
      await historyCtrl.close();
    });

    test('Transitioning standUp → 静默忽略', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(
        () => m.state,
      ).thenReturn(Transitioning(const StandUpCommand(), sub, null));

      final server = _simServer(brain, m);
      final result = await server.standUp(call, proto.Empty());
      expect(result, isA<proto.Empty>());

      await sub.cancel();
      await historyCtrl.close();
    });
  });

  group('setBodyHeight', () {
    test('finite target in stable state dispatches through CMS', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));

      final server = _simServer(brain, m);
      await server.setBodyHeight(call, proto.BodyHeightCommand(meters: 0.31));

      final action = verify(() => m.add(captureAny())).captured.single as A;
      expect(action, const A.setBodyHeight(0.31));

      await sub.cancel();
      await historyCtrl.close();
    });

    for (final invalid in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('non-finite target $invalid is ignored', () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));

        final server = _simServer(brain, m);
        final result = await server.setBodyHeight(
          call,
          proto.BodyHeightCommand(meters: invalid),
        );
        expect(result, isA<proto.Empty>());
        verifyNever(() => m.add(any()));

        await sub.cancel();
        await historyCtrl.close();
      });
    }

    test('transitioning state ignores target', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(
        () => m.state,
      ).thenReturn(Transitioning(const Command.standUp(), sub, null));

      final server = _simServer(brain, m);
      await server.setBodyHeight(call, proto.BodyHeightCommand(meters: 0.31));
      verifyNever(() => m.add(any()));

      await sub.cancel();
      await historyCtrl.close();
    });
  });
  test('setBodyHeight rate limits rapid updates', () async {
    final historyCtrl = StreamController<History>();
    final sub = historyCtrl.stream.listen((_) {});
    when(() => m.state).thenReturn(Standing(sub));

    final server = _simServer(brain, m);
    await server.setBodyHeight(call, proto.BodyHeightCommand(meters: 0.30));
    await server.setBodyHeight(call, proto.BodyHeightCommand(meters: 0.31));

    verify(() => m.add(any())).called(1);

    await sub.cancel();
    await historyCtrl.close();
  });

  test('setBodyHeight respects arbiter ownership', () async {
    final historyCtrl = StreamController<History>();
    final sub = historyCtrl.stream.listen((_) {});
    when(() => m.state).thenReturn(Standing(sub));
    final controlArbiter = ControlArbiter(m, timeout: Duration.zero);
    expect(
      controlArbiter.command(const A.standUp(), ControlSource.yunzhuo),
      isTrue,
    );
    clearInteractions(m);

    final server = UnifiedCmsServer(
      brain: brain,
      m: m,
      mode: CmsMode.hardware,
      arbiter: controlArbiter,
    );
    await server.setBodyHeight(call, proto.BodyHeightCommand(meters: 0.31));

    verifyNever(() => m.add(any()));
    expect(controlArbiter.owner, ControlSource.yunzhuo);

    controlArbiter.dispose();
    await sub.cancel();
    await historyCtrl.close();
  });

  test('initial profile clamps velocity axes and body height', () async {
    final historyCtrl = StreamController<History>();
    final sub = historyCtrl.stream.listen((_) {});
    when(() => m.state).thenReturn(Standing(sub));
    final server = UnifiedCmsServer(
      brain: brain,
      m: m,
      mode: CmsMode.simulation,
      initialProfile: _boundedProfile(
        'initial',
        minBodyHeightCommand: 0.25,
        maxBodyHeightCommand: 0.40,
        velocityCommandMin: (-0.4, -0.5, -0.6),
        velocityCommandMax: (0.4, 0.5, 0.6),
      ),
    );

    await server.walk(call, proto.Vector3(x: 2, y: -2, z: 3));
    final walkAction =
        verify(() => m.add(captureAny())).captured.single as CmdWalk;
    expect(walkAction.direction.x, closeTo(0.4, 1e-6));
    expect(walkAction.direction.y, closeTo(-0.5, 1e-6));
    expect(walkAction.direction.z, closeTo(0.6, 1e-6));
    clearInteractions(m);

    await server.setBodyHeight(call, proto.BodyHeightCommand(meters: 0.50));
    final heightAction =
        verify(() => m.add(captureAny())).captured.single as CmdSetBodyHeight;
    expect(heightAction.meters, 0.40);

    await sub.cancel();
    await historyCtrl.close();
  });

  test(
    'active profile manager takes precedence over initial profile',
    () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      final initialProfile = _boundedProfile('initial');
      final activeProfile = _boundedProfile(
        'active',
        minBodyHeightCommand: 0.30,
        maxBodyHeightCommand: 0.35,
        velocityCommandMin: (-0.1, -0.2, -0.3),
        velocityCommandMax: (0.1, 0.2, 0.3),
      );
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.simulation,
        initialProfile: initialProfile,
      );
      server.profileManager = ProfileManager(
        profiles: {'active': activeProfile},
        brain: brain,
        initial: 'active',
      );

      await server.walk(call, proto.Vector3(x: 1, y: -1, z: 1));
      final walkAction =
          verify(() => m.add(captureAny())).captured.single as CmdWalk;
      expect(walkAction.direction.x, closeTo(0.1, 1e-6));
      expect(walkAction.direction.y, closeTo(-0.2, 1e-6));
      expect(walkAction.direction.z, closeTo(0.3, 1e-6));
      clearInteractions(m);

      await server.setBodyHeight(call, proto.BodyHeightCommand(meters: 0.20));
      final heightAction =
          verify(() => m.add(captureAny())).captured.single as CmdSetBodyHeight;
      expect(heightAction.meters, 0.30);

      await sub.cancel();
      await historyCtrl.close();
    },
  );
  group('cms state', () {
    test('getCmsState returns authoritative grounded state', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Grounded(sub));

      final server = _simServer(brain, m);
      final state = await server.getCmsState(call, proto.Empty());

      expect(state.kind, proto.CmsStateKind.CMS_STATE_KIND_GROUNDED);
      expect(
        state.transition,
        proto.CmsTransitionKind.CMS_TRANSITION_KIND_NONE,
      );

      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'listenCmsState yields initial and subsequent state changes',
      () async {
        final historyCtrl = StreamController<History>.broadcast();
        final initialSub = historyCtrl.stream.listen((_) {});
        final nextSub = historyCtrl.stream.listen((_) {});
        final stateCtrl = StreamController<S>.broadcast();
        when(() => m.state).thenReturn(Grounded(initialSub));
        when(() => m.stream).thenAnswer((_) => stateCtrl.stream);

        final server = _simServer(brain, m);
        final statesFuture = server
            .listenCmsState(call, proto.Empty())
            .take(2)
            .toList();
        await Future<void>.delayed(Duration.zero);
        stateCtrl.add(Transitioning(const Command.sitDown(), nextSub, null));
        final states = await statesFuture;

        expect(states, hasLength(2));
        expect(states.first.kind, proto.CmsStateKind.CMS_STATE_KIND_GROUNDED);
        expect(
          states.last.kind,
          proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING,
        );
        expect(
          states.last.transition,
          proto.CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN,
        );

        await initialSub.cancel();
        await nextSub.cancel();
        await historyCtrl.close();
        await stateCtrl.close();
      },
    );
  });
}
