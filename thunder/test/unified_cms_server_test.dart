import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

// ─── Mock 类 ──────────────────────────────────────────────────────────

class _MockBrain extends Mock implements Brain {}

class _MockM extends Mock implements M {}

class _MockServiceCall extends Mock implements ServiceCall {}

class _MockRealJoint extends Mock implements RealJoint {}

class _MockX509Certificate extends Mock implements X509Certificate {}

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
UnifiedCmsServer _simServer(_MockBrain brain, _MockM m) =>
    UnifiedCmsServer(brain: brain, m: m, mode: CmsMode.simulation);

proto.WalkRequest _checkedWalk({
  required String token,
  required int sequence,
  double x = 0,
  double y = 0,
  double z = 0,
}) {
  final request = proto.WalkRequest(
    token: token,
    direction: proto.Vector3(x: x, y: y, z: z),
  );
  request.sequence = request.sequence + sequence;
  return request;
}

Future<proto.CommandAck> _acknowledgeInitialZero(
  UnifiedCmsServer server,
  ServiceCall call,
  String token, {
  int sequence = 1,
}) => server.walkChecked(call, _checkedWalk(token: token, sequence: sequence));

const _checkedWalkSpacing = Duration(milliseconds: 25);

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
    when(() => m.profileSwitchInProgress).thenReturn(false);
    when(() => m.isHandlingEvent).thenReturn(false);
    call = _MockServiceCall();
    when(() => call.remoteAddress).thenReturn(InternetAddress.loopbackIPv4);
    when(() => call.clientCertificate).thenReturn(null);
    when(() => call.isCanceled).thenReturn(false);
    when(() => call.isTimedOut).thenReturn(false);
    when(() => m.commandVersion).thenReturn(0);
    when(() => m.isClosed).thenReturn(false);

    // historyStream は late final で遅延初期化 — streaming RPC を呼ばない限り不要。
    // isModelLoaded のデフォルト = true（必要なテストで上書き）。
    when(() => brain.isModelLoaded).thenReturn(true);
    when(() => brain.standingPose).thenReturn(_zeros16);
    when(() => m.add(any())).thenReturn(null);
    when(() => m.state).thenReturn(const Zero());
  });

  test(
    'disable RPC blocks output immediately and reports missing confirmation',
    () async {
      final motor = _MockRealJoint();
      final stopped = Completer<void>();
      when(() => motor.disable()).thenAnswer((_) => stopped.future);
      when(() => motor.lastDisableConfirmed).thenReturn(false);
      when(() => motor.unconfirmedDisableJoints).thenReturn([15]);
      final changes = <bool>[];
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.simulation,
        motor: motor,
      )..onMotorEnableChanged = changes.add;
      final result = server.disable(call, proto.Empty());
      expect(changes, [false]);
      final assertion = expectLater(
        result,
        throwsA(
          isA<GrpcError>().having(
            (e) => e.code,
            'code',
            StatusCode.unavailable,
          ),
        ),
      );
      stopped.complete();
      await assertion;
    },
  );

  test('enable refusal never reports motor output enabled', () async {
    final motor = _MockRealJoint();
    when(() => motor.enable()).thenThrow(StateError('disable unconfirmed'));
    final changes = <bool>[];
    final server = UnifiedCmsServer(
      brain: brain,
      m: m,
      mode: CmsMode.simulation,
      motor: motor,
    )..onMotorEnableChanged = changes.add;
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
    expect(changes, [false]);
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
    test('hardware Standing cannot bypass R2 via administrative RPC', () async {
      final sub = const Stream<History>.empty().listen((_) {});
      addTearDown(sub.cancel);
      when(() => m.state).thenReturn(Standing(sub));
      final server =
          UnifiedCmsServer(brain: brain, m: m, mode: CmsMode.hardware)
            ..profileManager = ProfileManager(
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

  group('lease-aware motion control', () {
    test(
      'lease refuses queued FSM events and in-progress profile switches',
      () async {
        final sub = const Stream<History>.empty().listen((_) {});
        addTearDown(sub.cancel);
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m, timeout: Duration.zero);
        addTearDown(arbiter.dispose);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;
        addTearDown(server.dispose);
        for (final profileSwitch in [false, true]) {
          when(() => m.isHandlingEvent).thenReturn(!profileSwitch);
          when(() => m.profileSwitchInProgress).thenReturn(profileSwitch);
          final result = await server.acquireControl(
            call,
            proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
          );
          expect(result.accepted, isFalse);
          expect(
            result.reason,
            proto.CommandRejectReason.COMMAND_REJECT_REASON_FSM_NOT_READY,
          );
          expect(result.status.grpcLeaseActive, isFalse);
          expect(result.status.readyForWalk, isFalse);
          expect(arbiter.owner, isNull);
        }
        verifyNever(() => m.add(any()));
      },
    );

    test('motion principal map rejects ambiguous certificate ownership', () {
      for (final principals in <Map<String, List<int>>>[
        const {
          '': [1],
        },
        const {'lingtu-driver@sunrise': []},
        const {
          'lingtu-driver@sunrise': [1, 2, 3],
          'operator-console@sunrise': [1, 2, 3],
        },
      ]) {
        expect(
          () => UnifiedCmsServer(
            brain: brain,
            m: m,
            mode: CmsMode.hardware,
            hardwareMotionPrincipals: principals,
          ),
          throwsArgumentError,
        );
      }
    });

    test('hardware lease rejects non-loopback callers', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      when(
        () => call.remoteAddress,
      ).thenReturn(InternetAddress('192.168.114.100'));
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
      )..motorOutputEnabledProvider = () => true;

      await expectLater(
        server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'lingtu-driver@sunrise'),
        ),
        throwsA(
          isA<GrpcError>().having(
            (error) => error.code,
            'code',
            StatusCode.permissionDenied,
          ),
        ),
      );
      expect(arbiter.owner, isNull);

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'allowlisted remote peer without a client certificate is rejected',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        when(
          () => call.remoteAddress,
        ).thenReturn(InternetAddress('192.168.114.23'));
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
          hardwareMotionPeerAddresses: const {'192.168.114.23'},
        )..motorOutputEnabledProvider = () => true;

        await expectLater(
          server.acquireControl(
            call,
            proto.AcquireControlRequest(clientId: 'lingtu-driver@sunrise'),
          ),
          throwsA(
            isA<GrpcError>().having(
              (error) => error.code,
              'code',
              StatusCode.permissionDenied,
            ),
          ),
        );
        expect(arbiter.owner, isNull);
        verifyNever(() => m.add(any()));

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test('mTLS peer outside the IP allowlist is rejected', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      when(
        () => call.remoteAddress,
      ).thenReturn(InternetAddress('192.168.114.100'));
      when(() => call.clientCertificate).thenReturn(_MockX509Certificate());
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
        hardwareMotionPeerAddresses: const {'192.168.114.23'},
      )..motorOutputEnabledProvider = () => true;

      await expectLater(
        server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'lingtu-driver@sunrise'),
        ),
        throwsA(
          isA<GrpcError>().having(
            (error) => error.code,
            'code',
            StatusCode.permissionDenied,
          ),
        ),
      );
      expect(arbiter.owner, isNull);
      verifyNever(() => m.add(any()));

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'hardware lease and WalkChecked accept an mTLS allowlisted peer',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        when(
          () => call.remoteAddress,
        ).thenReturn(InternetAddress('192.168.114.23'));
        final certificate = _MockX509Certificate();
        when(() => certificate.der).thenReturn(Uint8List.fromList([1, 2, 3]));
        when(() => call.clientCertificate).thenReturn(certificate);
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
          hardwareMotionPeerAddresses: const {'192.168.114.23'},
          hardwareMotionPrincipals: const {
            'lingtu-driver@sunrise': [1, 2, 3],
          },
        );
        server.motorOutputEnabledProvider = () => true;
        server.criticalMotorFaultProvider = () => false;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'lingtu-driver@sunrise'),
        );
        final zero = await _acknowledgeInitialZero(server, call, lease.token);
        await Future<void>.delayed(_checkedWalkSpacing);
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 2, x: 0.2),
        );

        expect(lease.accepted, isTrue);
        expect(zero.accepted, isTrue);
        expect(ack.accepted, isTrue);
        expect(ack.status.ownerId, 'lingtu-driver@sunrise');
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(2));
        expect(captured.first.direction.length, 0);
        expect(captured.last.direction.x, closeTo(0.2, 1e-6));

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'allowlisted mTLS peer with a different leaf certificate is rejected',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        when(
          () => call.remoteAddress,
        ).thenReturn(InternetAddress('192.168.114.23'));
        final certificate = _MockX509Certificate();
        when(() => certificate.der).thenReturn(Uint8List.fromList([9, 9, 9]));
        when(() => call.clientCertificate).thenReturn(certificate);
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
          hardwareMotionPeerAddresses: const {'192.168.114.23'},
          hardwareMotionPrincipals: const {
            'lingtu-driver@sunrise': [1, 2, 3],
          },
        )..motorOutputEnabledProvider = () => true;

        await expectLater(
          server.acquireControl(
            call,
            proto.AcquireControlRequest(clientId: 'lingtu-driver@sunrise'),
          ),
          throwsA(
            isA<GrpcError>().having(
              (error) => error.code,
              'code',
              StatusCode.permissionDenied,
            ),
          ),
        );
        expect(arbiter.owner, isNull);
        verifyNever(() => m.add(any()));

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'another authorized principal cannot renew the active lease',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        when(
          () => call.remoteAddress,
        ).thenReturn(InternetAddress('192.168.114.23'));
        final certificate = _MockX509Certificate();
        when(() => certificate.der).thenReturn(Uint8List.fromList([1, 2, 3]));
        when(() => call.clientCertificate).thenReturn(certificate);
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
          hardwareMotionPeerAddresses: const {'192.168.114.23'},
          hardwareMotionPrincipals: const {
            'lingtu-driver@sunrise': [1, 2, 3],
            'operator-console@sunrise': [4, 5, 6],
          },
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'lingtu-driver@sunrise'),
        );
        when(() => certificate.der).thenReturn(Uint8List.fromList([4, 5, 6]));

        await expectLater(
          server.renewControlLease(
            call,
            proto.ControlLeaseRequest(token: lease.token),
          ),
          throwsA(
            isA<GrpcError>().having(
              (error) => error.code,
              'code',
              StatusCode.permissionDenied,
            ),
          ),
        );
        final status = await server.getControlStatus(call, proto.Empty());
        expect(status.grpcLeaseActive, isTrue);
        expect(status.ownerId, 'lingtu-driver@sunrise');
        expect(arbiter.owner, ControlSource.grpc);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'allowlisted peer without an authenticated principal cannot call posture RPCs',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        when(
          () => call.remoteAddress,
        ).thenReturn(InternetAddress('192.168.114.23'));
        when(() => call.clientCertificate).thenReturn(_MockX509Certificate());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
          hardwareMotionPeerAddresses: const {'192.168.114.23'},
        );

        await expectLater(
          server.standUp(call, proto.Empty()),
          throwsA(
            isA<GrpcError>().having(
              (error) => error.code,
              'code',
              StatusCode.permissionDenied,
            ),
          ),
        );
        verifyNever(() => m.add(any()));

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test('authenticated motion principal can stand up and sit down', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Grounded(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      when(
        () => call.remoteAddress,
      ).thenReturn(InternetAddress('192.168.114.23'));
      final certificate = _MockX509Certificate();
      when(() => certificate.der).thenReturn(Uint8List.fromList([1, 2, 3]));
      when(() => call.clientCertificate).thenReturn(certificate);
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
        hardwareMotionPeerAddresses: const {'192.168.114.23'},
        hardwareMotionPrincipals: const {
          'lingtu-driver@robot': [1, 2, 3],
        },
      )..motorOutputEnabledProvider = () => true;

      await server.standUp(call, proto.Empty());
      verify(() => m.add(const A.standUp())).called(1);

      when(() => m.state).thenReturn(Standing(sub));
      await server.sitDown(call, proto.Empty());
      verify(() => m.add(const A.sitDown())).called(1);

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'hardware lease rejects a claimed identity that is not the caller',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        await expectLater(
          server.acquireControl(
            call,
            proto.AcquireControlRequest(clientId: 'legacy-python-driver'),
          ),
          throwsA(
            isA<GrpcError>().having(
              (error) => error.code,
              'code',
              StatusCode.permissionDenied,
            ),
          ),
        );
        expect(arbiter.owner, isNull);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'active local gRPC lease cannot be replaced by a second acquire',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        final first = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final second = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final renewed = await server.renewControlLease(
          call,
          proto.ControlLeaseRequest(token: first.token),
        );

        expect(first.accepted, isTrue);
        expect(second.accepted, isFalse);
        expect(
          second.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_CONTROL_BUSY,
        );
        expect(renewed.accepted, isTrue);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test('acquireControl rejects when motor output is disabled', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
      )..motorOutputEnabledProvider = () => false;

      final lease = await server.acquireControl(
        call,
        proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
      );

      expect(lease.accepted, isFalse);
      expect(
        lease.reason,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTORS_DISABLED,
      );
      expect(lease.status.readyForWalk, isFalse);

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'new hardware lease rejects nonzero motion until zero is accepted',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        );
        server.motorOutputEnabledProvider = () => true;
        server.criticalMotorFaultProvider = () => false;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final rejected = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 41, x: 0.2),
        );
        final zero = await _acknowledgeInitialZero(
          server,
          call,
          lease.token,
          sequence: 41,
        );
        await Future<void>.delayed(_checkedWalkSpacing);
        final accepted = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 42, x: 0.2),
        );

        expect(lease.accepted, isTrue);
        expect(lease.status.readyForWalk, isFalse);
        expect(rejected.accepted, isFalse);
        expect(
          rejected.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_CONTROL_BUSY,
        );
        expect(rejected.status.readyForWalk, isFalse);
        expect(zero.accepted, isTrue);
        expect(zero.status.readyForWalk, isTrue);
        expect(accepted.accepted, isTrue);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(2));
        expect(captured.first.direction.length, 0);
        expect(captured.last.direction.x, closeTo(0.2, 1e-6));

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test('WalkChecked rejects zero sequence as an order violation', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
      )..motorOutputEnabledProvider = () => true;

      final lease = await server.acquireControl(
        call,
        proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
      );
      final ack = await server.walkChecked(
        call,
        _checkedWalk(token: lease.token, sequence: 0),
      );

      expect(ack.accepted, isFalse);
      expect(
        ack.reason,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED,
      );
      expect(ack.status.grpcLeaseActive, isFalse);
      expect(arbiter.owner, isNull);
      verifyNever(() => m.add(any(that: isA<CmdWalk>())));

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'exact WalkChecked retry returns the cached ACK without redispatch',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final request = _checkedWalk(token: lease.token, sequence: 73);
        final first = await server.walkChecked(call, request);
        await Future<void>.delayed(_checkedWalkSpacing);
        final beforeRetry = await server.getControlStatus(call, proto.Empty());
        final duplicate = await server.walkChecked(call, request.deepCopy());

        expect(first.accepted, isTrue);
        expect(duplicate.accepted, isTrue);
        expect(
          duplicate.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE,
        );
        expect(duplicate.sequence.toInt(), 73);
        expect(duplicate.status.lastAcceptedSequence.toInt(), 73);
        expect(duplicate.status.grpcLeaseActive, isTrue);
        expect(
          duplicate.status.leaseRemainingMs,
          greaterThan(beforeRetry.leaseRemainingMs),
        );
        expect(duplicate.status.acceptedCount, first.status.acceptedCount);
        verify(() => m.add(any(that: isA<CmdWalk>()))).called(1);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'same sequence with a different payload is rejected and revoked',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final first = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 500),
        );
        await Future<void>.delayed(_checkedWalkSpacing);
        final conflict = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 500, x: 0.2),
        );

        expect(first.accepted, isTrue);
        expect(conflict.accepted, isFalse);
        expect(
          conflict.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED,
        );
        expect(conflict.status.grpcLeaseActive, isFalse);
        expect(arbiter.owner, isNull);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(2));
        expect(captured, everyElement(isA<CmdWalk>()));
        expect(
          captured.every((command) => command.direction.length == 0),
          isTrue,
        );

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test('sequence rollback is rejected without dispatch', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
      )..motorOutputEnabledProvider = () => true;

      final lease = await server.acquireControl(
        call,
        proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
      );
      final first = await server.walkChecked(
        call,
        _checkedWalk(token: lease.token, sequence: 100),
      );
      await Future<void>.delayed(_checkedWalkSpacing);
      final rollback = await server.walkChecked(
        call,
        _checkedWalk(token: lease.token, sequence: 99, x: 0.2),
      );

      expect(first.accepted, isTrue);
      expect(rollback.accepted, isFalse);
      expect(
        rollback.reason,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED,
      );
      expect(rollback.status.grpcLeaseActive, isFalse);
      expect(arbiter.owner, isNull);
      final captured = verify(
        () => m.add(captureAny(that: isA<CmdWalk>())),
      ).captured.cast<CmdWalk>();
      expect(captured, hasLength(2));
      expect(
        captured.every((command) => command.direction.length == 0),
        isTrue,
      );

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test('sequence gap is rejected without dispatch', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Standing(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
      )..motorOutputEnabledProvider = () => true;

      final lease = await server.acquireControl(
        call,
        proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
      );
      final first = await server.walkChecked(
        call,
        _checkedWalk(token: lease.token, sequence: 100),
      );
      await Future<void>.delayed(_checkedWalkSpacing);
      final gap = await server.walkChecked(
        call,
        _checkedWalk(token: lease.token, sequence: 102, x: 0.2),
      );

      expect(first.accepted, isTrue);
      expect(gap.accepted, isFalse);
      expect(
        gap.reason,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED,
      );
      expect(gap.status.grpcLeaseActive, isFalse);
      expect(arbiter.owner, isNull);
      final captured = verify(
        () => m.add(captureAny(that: isA<CmdWalk>())),
      ).captured.cast<CmdWalk>();
      expect(captured, hasLength(2));
      expect(
        captured.every((command) => command.direction.length == 0),
        isTrue,
      );

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'accepted WalkChecked renews the LingTu lease and returns ACK',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        );
        server.motorOutputEnabledProvider = () => true;
        server.criticalMotorFaultProvider = () => false;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final zero = await _acknowledgeInitialZero(
          server,
          call,
          lease.token,
          sequence: 17,
        );
        await Future<void>.delayed(_checkedWalkSpacing);
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 18, x: 0.2),
        );

        expect(lease.accepted, isTrue);
        expect(zero.accepted, isTrue);
        expect(ack.accepted, isTrue);
        expect(
          ack.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE,
        );
        expect(ack.status.readyForWalk, isTrue);
        expect(ack.status.ownerId, 'local-grpc@bsrl1');
        expect(ack.status.lastAcceptedSequence.toInt(), 18);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(2));
        expect(captured.first.direction.length, 0);
        expect(captured.last.direction.x, closeTo(0.2, 1e-6));

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'release queues zero after a walk accepted while FSM is still Standing',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final zero = await _acknowledgeInitialZero(server, call, lease.token);
        expect(zero.accepted, isTrue);
        await Future<void>.delayed(_checkedWalkSpacing);
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 2, x: 0.2),
        );
        await server.releaseControl(
          call,
          proto.ControlLeaseRequest(token: lease.token),
        );

        expect(ack.accepted, isTrue);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(3));
        expect(captured.first.direction.length, 0);
        expect(captured[1].direction.x, closeTo(0.2, 1e-6));
        expect(captured.last.direction.length, 0);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'arbiter timeout revokes an active gRPC lease and queues zero',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(
          m,
          timeout: const Duration(milliseconds: 60),
        );
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
          grpcLeaseTimeout: const Duration(milliseconds: 100),
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final zero = await _acknowledgeInitialZero(server, call, lease.token);
        expect(zero.accepted, isTrue);
        await Future<void>.delayed(_checkedWalkSpacing);
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 2, x: 0.2),
        );
        expect(ack.accepted, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 75));

        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(3));
        expect(captured.first.direction.length, 0);
        expect(captured[1].direction.x, closeTo(0.2, 1e-6));
        expect(captured.last.direction.length, 0);
        final status = await server.getControlStatus(call, proto.Empty());
        expect(status.grpcLeaseActive, isFalse);
        expect(arbiter.owner, isNull);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'YUNZHUO preemption invalidates the lease without overwriting its walk',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final zero = await _acknowledgeInitialZero(server, call, lease.token);
        expect(zero.accepted, isTrue);
        await Future<void>.delayed(_checkedWalkSpacing);
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 2, x: 0.2),
        );
        expect(ack.accepted, isTrue);

        expect(
          arbiter.command(A.walk(Vector3(0.4, 0, 0)), ControlSource.yunzhuo),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);

        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(3));
        expect(captured.last.direction.x, closeTo(0.4, 1e-6));
        final status = await server.getControlStatus(call, proto.Empty());
        expect(status.grpcLeaseActive, isFalse);
        expect(status.owner, proto.ControlOwner.CONTROL_OWNER_YUNZHUO);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'Disable revokes an active lease before disabling motor output',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        var motorsEnabled = true;
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        );
        server.motorOutputEnabledProvider = () => motorsEnabled;
        server.onMotorEnableChanged = (enabled) => motorsEnabled = enabled;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final zero = await _acknowledgeInitialZero(server, call, lease.token);
        expect(zero.accepted, isTrue);
        await Future<void>.delayed(_checkedWalkSpacing);
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 2, x: 0.2),
        );
        await server.disable(call, proto.Empty());
        final status = await server.getControlStatus(call, proto.Empty());

        expect(ack.accepted, isTrue);
        expect(motorsEnabled, isFalse);
        expect(status.grpcLeaseActive, isFalse);
        expect(status.readyForWalk, isFalse);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(3));
        expect(captured.last.direction.length, 0);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test('expired lease sends one zero walk while FSM is Walking', () async {
      final historyCtrl = StreamController<History>();
      final sub = historyCtrl.stream.listen((_) {});
      when(() => m.state).thenReturn(Walking(sub));
      when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
      final arbiter = ControlArbiter(m);
      final server = UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
        grpcLeaseTimeout: const Duration(milliseconds: 20),
      );
      server.motorOutputEnabledProvider = () => true;
      server.criticalMotorFaultProvider = () => false;

      final lease = await server.acquireControl(
        call,
        proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
      );
      expect(lease.accepted, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 35));

      final captured = verify(
        () => m.add(captureAny(that: isA<CmdWalk>())),
      ).captured.cast<CmdWalk>();
      expect(captured, hasLength(1));
      expect(captured.single.direction.length, 0);
      expect(captured.single.forceWheelStop, isTrue);
      final status = await server.getControlStatus(call, proto.Empty());
      expect(status.grpcLeaseActive, isFalse);
      expect(status.readyForWalk, isFalse);
      expect(
        status.lastDecision,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_LEASE_EXPIRED,
      );

      await server.dispose();
      arbiter.dispose();
      await sub.cancel();
      await historyCtrl.close();
    });

    test(
      'lease renewal is rejected and revoked when motors become disabled',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Standing(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        var motorsEnabled = true;
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        );
        server.motorOutputEnabledProvider = () => motorsEnabled;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        motorsEnabled = false;
        final renewed = await server.renewControlLease(
          call,
          proto.ControlLeaseRequest(token: lease.token),
        );

        expect(renewed.accepted, isFalse);
        expect(
          renewed.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTORS_DISABLED,
        );
        expect(renewed.status.grpcLeaseActive, isFalse);
        expect(arbiter.owner, isNull);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'WalkChecked motor fault revokes lease and immediately sends zero',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Walking(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        var criticalFault = false;
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        );
        server.motorOutputEnabledProvider = () => true;
        server.criticalMotorFaultProvider = () => criticalFault;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        criticalFault = true;
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 1, x: 0.2),
        );

        expect(ack.accepted, isFalse);
        expect(
          ack.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTOR_FAULT,
        );
        expect(ack.status.grpcLeaseActive, isFalse);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(1));
        expect(captured.single.direction.length, 0);
        expect(captured.single.forceWheelStop, isTrue);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'invalid WalkChecked vector revokes lease and immediately sends zero',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Walking(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final ack = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 1, x: double.nan),
        );

        expect(ack.accepted, isFalse);
        expect(
          ack.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_INVALID_VECTOR,
        );
        expect(ack.status.grpcLeaseActive, isFalse);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(1));
        expect(captured.single.direction.length, 0);
        expect(captured.single.forceWheelStop, isTrue);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );

    test(
      'rate-limited WalkChecked revokes lease and immediately sends zero',
      () async {
        final historyCtrl = StreamController<History>();
        final sub = historyCtrl.stream.listen((_) {});
        when(() => m.state).thenReturn(Walking(sub));
        when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
        final arbiter = ControlArbiter(m);
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
          arbiter: arbiter,
        )..motorOutputEnabledProvider = () => true;

        final lease = await server.acquireControl(
          call,
          proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
        );
        final zero = await _acknowledgeInitialZero(server, call, lease.token);
        expect(zero.accepted, isTrue);
        await Future<void>.delayed(_checkedWalkSpacing);
        final first = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 2, x: 0.2),
        );
        final second = await server.walkChecked(
          call,
          _checkedWalk(token: lease.token, sequence: 3, x: 0.2),
        );

        expect(first.accepted, isTrue);
        expect(second.accepted, isFalse);
        expect(
          second.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED,
        );
        expect(second.status.grpcLeaseActive, isFalse);
        final captured = verify(
          () => m.add(captureAny(that: isA<CmdWalk>())),
        ).captured.cast<CmdWalk>();
        expect(captured, hasLength(3));
        expect(captured.last.direction.length, 0);

        await server.dispose();
        arbiter.dispose();
        await sub.cancel();
        await historyCtrl.close();
      },
    );
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
