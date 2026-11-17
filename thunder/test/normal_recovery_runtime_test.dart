import 'dart:async';
import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:thunder/src/recovery/normal_recovery_runtime.dart';
import 'package:thunder/src/recovery/recovery.dart';
import 'package:thunder/src/server/recovery_service.dart';
import 'package:test/test.dart';

class Inference implements RecoveryInference {
  int resets = 0;
  Completer<void>? resetWait;
  Completer<List<double>>? inferWait;
  @override
  Future<void> reset(int epoch) {
    resets++;
    return resetWait?.future ?? Future<void>.value();
  }

  @override
  Future<List<double>> infer(int epoch, int seq, RecoverySample sample) =>
      inferWait?.future ??
      Future<List<double>>.value(List<double>.filled(16, 0));
}

class Fixture {
  final inference = Inference();
  int now = 0, writes = 0, disables = 0, restores = 0;
  bool enabled = false, idle = true, healthy = true, confirmDisable = true;
  Completer<void>? enableWait;
  late final NormalRecoveryRuntime runtime;
  Fixture({bool verified = true}) {
    runtime = NormalRecoveryRuntime(
      inference: inference,
      sample: () => RecoverySample(
        angular: [0, 0, 0],
        gravity: [0, 0, -1],
        q: List<double>.filled(16, 0),
        dq: List<double>.filled(16, 0),
        ageMs: 0,
        healthy: healthy,
      ),
      canEnter: () => idle,
      healthy: () => healthy,
      enabled: () => enabled,
      enableHardware: (_) async {
        await enableWait?.future;
        enabled = true;
      },
      disableHardware: () async {
        disables++;
        enabled = false;
        return confirmDisable;
      },
      sendHardware: (_) {
        writes++;
      },
      restoreNormalGains: () {
        restores++;
      },
      nowUs: () => now,
      verified: verified,
      lower: List<double>.filled(16, -4),
      upper: List<double>.filled(16, 4),
    );
  }
  String enter() => runtime.enter('operator', 'entry');
}

void main() {
  test('unverified, moving and enabled sessions cannot select recovery', () {
    expect(() => Fixture(verified: false).enter(), throwsStateError);
    final f = Fixture()..idle = false;
    expect(f.enter, throwsStateError);
    f.idle = true;
    f.enabled = true;
    expect(f.enter, throwsStateError);
  });
  test(
    'selection does not enable; wrong identity and token cannot act',
    () async {
      final f = Fixture();
      final token = f.enter();
      expect(f.enabled, isFalse);
      expect(f.enter(), token);
      expect(() => f.runtime.heartbeat('other', token), throwsStateError);
      expect(() => f.runtime.heartbeat('operator', 'wrong'), throwsStateError);
      await f.runtime.enable('operator', token);
      expect(f.enabled, isTrue);
      expect(f.runtime.controller.phase, RecoveryPhase.waiting);
    },
  );
  test('start is idempotent and cancel cannot replay the operation', () async {
    final f = Fixture();
    final token = f.enter();
    await f.runtime.enable('operator', token);
    expect(await f.runtime.start('operator', token, 'action'), isTrue);
    expect(await f.runtime.start('operator', token, 'action'), isTrue);
    expect(f.inference.resets, 2);
    await f.runtime.cancel('operator', token);
    expect(f.runtime.stopConfirmed, isTrue);
    expect(
      () => f.runtime.start('operator', token, 'action'),
      throwsStateError,
    );
    expect(f.runtime.selected, isTrue);
    await f.runtime.exit('operator', token);
    expect(f.runtime.selected, isFalse);
    expect(f.restores, 1);
  });
  test('expired lease cannot be renewed and stops once', () async {
    final f = Fixture();
    final token = f.enter();
    await f.runtime.enable('operator', token);
    f.now = 300000;
    await f.runtime.tick();
    await f.runtime.tick();
    expect(f.enabled, isFalse);
    expect(f.disables, 1);
    expect(() => f.runtime.heartbeat('operator', token), throwsStateError);
  });
  test('late inference after cancellation cannot reach hardware', () async {
    final f = Fixture();
    final token = f.enter();
    await f.runtime.enable('operator', token);
    await f.runtime.start('operator', token, 'action');
    f.inference.inferWait = Completer<List<double>>();
    final tick = f.runtime.tick();
    await f.runtime.cancel('operator', token);
    f.inference.inferWait!.complete(List<double>.filled(16, 0));
    await tick;
    expect(f.writes, 0);
  });
  test('enable completing after cancel is disabled again', () async {
    final f = Fixture();
    final token = f.enter();
    f.enableWait = Completer<void>();
    final enable = f.runtime.enable('operator', token);
    final rejection = expectLater(enable, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await f.runtime.cancel('operator', token);
    f.enableWait!.complete();
    await rejection;
    expect(f.enabled, isFalse);
    expect(f.disables, 2);
  });
  test('unconfirmed disable keeps normal mode locked', () async {
    final f = Fixture()..confirmDisable = false;
    final token = f.enter();
    await expectLater(f.runtime.exit('operator', token), throwsStateError);
    expect(f.runtime.selected, isTrue);
    expect(f.restores, 0);
  });
  test('new session rejects old token and permits a new operation', () async {
    final f = Fixture();
    final token = f.enter();
    await f.runtime.exit('operator', token);
    final next = f.enter();
    expect(next, isNot(token));
    expect(() => f.runtime.heartbeat('operator', token), throwsStateError);
    await f.runtime.enable('operator', next);
    expect(await f.runtime.start('operator', next, 'new'), isTrue);
  });
  test(
    'real loopback recovery RPC reports and gates selected runtime',
    () async {
      final f = Fixture();
      final server = Server.create(
        services: [RecoveryService(f.runtime, (_) => 'operator')],
      );
      await server.serve(address: '127.0.0.1', port: 0);
      final channel = ClientChannel(
        '127.0.0.1',
        port: server.port!,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      );
      final client = proto.RobotRecoveryClient(channel);
      try {
        final selected = await client.enter(
          proto.RecoveryStartRequest(operationId: 'entry'),
        );
        expect(selected.selected, isTrue);
        expect(selected.sessionToken, isNotEmpty);
        final session = proto.RecoverySessionRequest(
          sessionToken: selected.sessionToken,
        );
        await client.enable(session);
        final accepted = await client.start(
          proto.RecoveryStartRequest(
            operationId: 'action',
            sessionToken: selected.sessionToken,
          ),
        );
        expect(
          accepted.decision,
          proto.RecoveryActionDecision.RECOVERY_ACTION_DECISION_ACCEPTED,
        );
        final status = await client.getStatus(proto.Empty());
        expect(status.sessionToken, isEmpty);
        expect(status.phase, proto.RecoveryPhase.RECOVERY_PHASE_RECOVERING);
        final exited = await client.exit(session);
        expect(exited.selected, isFalse);
        expect(exited.motorDisableConfirmed, isTrue);
      } finally {
        await channel.shutdown();
        await server.shutdown();
      }
    },
  );
}
