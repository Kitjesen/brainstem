import 'dart:async';
import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockBrain extends Mock implements Brain {}

class MockM extends Mock implements M {}

class MockCall extends Mock implements ServiceCall {}

void main() {
  late MockBrain brain;
  late MockM m;
  late MockCall call;
  late ControlArbiter arbiter;
  late UnifiedCmsServer server;
  late StreamSubscription<History> sub;
  late S state;
  var enabled = true;
  var fault = false;
  var handling = false;
  var switching = false;
  var enablePending = false;

  setUpAll(() => registerFallbackValue(const A.init()));
  setUp(() {
    brain = MockBrain();
    m = MockM();
    call = MockCall();
    sub = const Stream<History>.empty().listen((_) {});
    state = Walking(sub);
    enabled = true;
    fault = handling = switching = enablePending = false;
    when(() => m.state).thenAnswer((_) => state);
    when(() => m.stream).thenAnswer((_) => const Stream<S>.empty());
    when(() => m.isHandlingEvent).thenAnswer((_) => handling);
    when(() => m.profileSwitchInProgress).thenAnswer((_) => switching);
    when(() => m.add(any())).thenReturn(null);
    when(() => brain.isModelLoaded).thenReturn(true);
    when(() => call.remoteAddress).thenReturn(InternetAddress.loopbackIPv4);
    when(() => call.clientCertificate).thenReturn(null);
    when(() => call.isCanceled).thenReturn(false);
    when(() => call.isTimedOut).thenReturn(false);
    arbiter = ControlArbiter(m, timeout: Duration.zero);
    server =
        UnifiedCmsServer(
            brain: brain,
            m: m,
            mode: CmsMode.hardware,
            arbiter: arbiter,
          )
          ..motorOutputEnabledProvider = (() => enabled)
          ..criticalMotorFaultProvider = (() => fault)
          ..externalMotorEnablePendingProvider = (() => enablePending);
  });
  tearDown(() async {
    await server.dispose();
    arbiter.dispose();
    await sub.cancel();
  });
  Matcher rejected(int code) =>
      throwsA(isA<GrpcError>().having((error) => error.code, 'code', code));

  test(
    'Walking StandUp dispatches the existing posture action, not a no-op',
    () async {
      await server.standUp(call, proto.Empty());
      verify(() => m.add(const A.standUp())).called(1);
      verifyNever(() => m.add(any(that: isA<CmdWalk>())));
    },
  );

  test('Standing StandUp remains idempotent', () async {
    state = Standing(sub);
    await server.standUp(call, proto.Empty());
    verifyNever(() => m.add(any()));
  });

  test(
    'nonzero walking command cannot jump directly to the fixed pose',
    () async {
      final simulation = UnifiedCmsServer(brain: brain, m: m);
      try {
        await simulation.walk(call, proto.Vector3(x: 0.5));
        await expectLater(
          simulation.standUp(call, proto.Empty()),
          rejected(StatusCode.failedPrecondition),
        );
        verifyNever(() => m.add(const A.standUp()));
      } finally {
        await simulation.dispose();
      }
    },
  );

  test('active lease blocks StandUp until explicit release', () async {
    final lease = await server.acquireControl(
      call,
      proto.AcquireControlRequest(clientId: 'local-grpc@bsrl1'),
    );
    expect(lease.accepted, isTrue);
    await expectLater(
      server.standUp(call, proto.Empty()),
      rejected(StatusCode.failedPrecondition),
    );
    verifyNever(() => m.add(const A.standUp()));
    await server.releaseControl(
      call,
      proto.ControlLeaseRequest(token: lease.token),
    );
    await server.standUp(call, proto.Empty());
    verify(() => m.add(const A.standUp())).called(1);
  });

  for (final reason in [
    'disabled',
    'fault',
    'handling',
    'switching',
    'enabling',
    'transitioning',
    'cancelled',
    'timed-out',
  ]) {
    test('$reason refuses Walk-to-Standing without dispatch', () async {
      switch (reason) {
        case 'disabled':
          enabled = false;
        case 'fault':
          fault = true;
        case 'handling':
          handling = true;
        case 'switching':
          switching = true;
        case 'enabling':
          enablePending = true;
        case 'transitioning':
          state = Transitioning(const Command.standUp(), sub, null);
        case 'cancelled':
          when(() => call.isCanceled).thenReturn(true);
        case 'timed-out':
          when(() => call.isTimedOut).thenReturn(true);
      }
      await expectLater(
        server.standUp(call, proto.Empty()),
        rejected(StatusCode.failedPrecondition),
      );
      verifyNever(() => m.add(any()));
    });
  }

  test('Yunzhuo ownership cannot be stolen by StandUp', () async {
    expect(arbiter.tryAcquire(ControlSource.yunzhuo), isTrue);
    await expectLater(
      server.standUp(call, proto.Empty()),
      rejected(StatusCode.aborted),
    );
    verifyNever(() => m.add(any()));
  });

  test('unauthorized peer cannot dispatch StandUp', () async {
    when(() => call.remoteAddress).thenReturn(InternetAddress('192.0.2.9'));
    await expectLater(
      server.standUp(call, proto.Empty()),
      rejected(StatusCode.permissionDenied),
    );
    verifyNever(() => m.add(any()));
  });
}
