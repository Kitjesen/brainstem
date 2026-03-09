import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_message/han_dog_message.dart' as proto;
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

// ─── Mock 类 ──────────────────────────────────────────────────────────

class _MockBrain extends Mock implements Brain {}

class _MockM extends Mock implements M {}

class _MockServiceCall extends Mock implements ServiceCall {}

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

/// 创建仿真模式服务器（无 arbiter，无 simInjector）。
UnifiedCmsServer _simServer(_MockBrain brain, _MockM m) => UnifiedCmsServer(
      brain: brain,
      m: m,
      mode: CmsMode.simulation,
    );

void main() {
  late _MockBrain brain;
  late _MockM m;
  late _MockServiceCall call;

  setUpAll(() {
    registerFallbackValue(const A.init());
    registerFallbackValue(JointsMatrix.zero());
    registerFallbackValue(GestureLibrary(standingPose: JointsMatrix.zero()));
    registerFallbackValue(
        StandardObservationBuilder(standingPose: JointsMatrix.zero()));
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
    test('NaN 方向向量 → GrpcError.invalidArgument', () async {
      final server = _simServer(brain, m);
      await expectLater(
        server.walk(call, proto.Vector3(x: double.nan, y: 0, z: 0)),
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.invalidArgument)),
      );
    });

    test('Inf 方向向量 → GrpcError.invalidArgument', () async {
      final server = _simServer(brain, m);
      await expectLater(
        server.walk(call, proto.Vector3(x: double.infinity, y: 0, z: 0)),
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.invalidArgument)),
      );
    });

    test('幅值超过 3.0 → GrpcError.invalidArgument', () async {
      final server = _simServer(brain, m);
      await expectLater(
        server.walk(call, proto.Vector3(x: 3.1, y: 0, z: 0)),
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.invalidArgument)),
      );
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
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.failedPrecondition)),
      );
    });

    test('模型未加载时调用 tick → GrpcError.failedPrecondition', () async {
      when(() => brain.isModelLoaded).thenReturn(false);
      final server = _simServer(brain, m);
      await expectLater(
        server.tick(call, proto.Empty()),
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.failedPrecondition)),
      );
    });
  });

  // ─── step モードガード ────────────────────────────────────────────────

  group('step — 模式守卫', () {
    test('无 simInjector 时调用 step → GrpcError.failedPrecondition', () async {
      // simInjector 为 null（_simServer 不传入 simInjector）
      final server = _simServer(brain, m);
      await expectLater(
        server.step(call, proto.SimState()),
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.failedPrecondition)),
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
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.unimplemented)),
      );
    });

    test('已配置 profileManager → 返回正确的 ProfileInfo', () async {
      final server = _simServer(brain, m);
      server.profileManager = ProfileManager(
        profiles: {
          'mini': _profile('mini'),
          'fast': _profile('fast'),
        },
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
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.unimplemented)),
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
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.failedPrecondition)),
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
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.invalidArgument)),
      );

      await sub.cancel();
      await ctrl.close();
    });
  });

  group('motion preconditions', () {
    test('Grounded walk returns failedPrecondition', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Grounded(sub));

      final server = _simServer(brain, m);
      await expectLater(
        server.walk(call, proto.Vector3(x: 0.5, y: 0, z: 0)),
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.failedPrecondition)),
      );

      await sub.cancel();
      await historyCtrl.close();
    });

    test('Transitioning standUp returns failedPrecondition', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(
        Transitioning(const StandUpCommand(), sub, null),
      );

      final server = _simServer(brain, m);
      await expectLater(
        server.standUp(call, proto.Empty()),
        throwsA(isA<GrpcError>()
            .having((e) => e.code, 'code', StatusCode.failedPrecondition)),
      );

      await sub.cancel();
      await historyCtrl.close();
    });
  });

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

    test('listenCmsState yields initial and subsequent state changes', () async {
      final historyCtrl = StreamController<History>.broadcast();
      final initialSub = historyCtrl.stream.listen((_) {});
      final nextSub = historyCtrl.stream.listen((_) {});
      final stateCtrl = StreamController<S>.broadcast();
      when(() => m.state).thenReturn(Grounded(initialSub));
      when(() => m.stream).thenAnswer((_) => stateCtrl.stream);

      final server = _simServer(brain, m);
      final statesFuture =
          server.listenCmsState(call, proto.Empty()).take(2).toList();
      await Future<void>.delayed(Duration.zero);
      stateCtrl.add(Transitioning(const Command.sitDown(), nextSub, null));
      final states = await statesFuture;

      expect(states, hasLength(2));
      expect(states.first.kind, proto.CmsStateKind.CMS_STATE_KIND_GROUNDED);
      expect(states.last.kind, proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING);
      expect(
        states.last.transition,
        proto.CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN,
      );

      await initialSub.cancel();
      await nextSub.cancel();
      await historyCtrl.close();
      await stateCtrl.close();
    });
  });
}
