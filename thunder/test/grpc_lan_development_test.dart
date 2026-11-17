import 'dart:async';
import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart' as grpc;
import 'package:thunder/thunder.dart';
import 'package:thunder/src/app/config.dart';
import 'package:thunder/src/server/grpc_lan_development.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

class _Call extends Mock implements grpc.ServiceCall {}

class _Method extends Mock implements grpc.ServiceMethod<int, int> {}

class _Brain extends Mock implements Brain {}

class _Machine extends Mock implements M {}

class _LanConfig extends ThunderConfig {
  @override
  String get grpcTransport => 'lan-dev';
  @override
  String get grpcLanAddress => '192.168.66.64';
  @override
  Set<String> get grpcAllowedIps => const {'192.168.66.94'};
  @override
  String get profileDir => Directory.current.path;
  @override
  String get grpcTlsClientCaFile => 'retained-but-unused-ca.pem';
  @override
  String get grpcTlsCertificateFile => 'retained-but-unused-cert.pem';
  @override
  String get grpcTlsPrivateKeyFile => 'retained-but-unused-key.pem';
  @override
  Map<String, String> get locomotionPrincipalCertificateFiles => const {
    'retained@robot': '/retained-but-unused-client.pem',
  };
}

List<int> _encode(int value) => [value];
int _decode(List<int> value) => value.single;

class _Ping extends grpc.Service {
  @override
  String get $name => 'lan.Ping';
  _Ping() {
    $addMethod(
      grpc.ServiceMethod<int, int>(
        'Ping',
        (grpc.ServiceCall call, Future<int> request) => request,
        false,
        false,
        _decode,
        _encode,
      ),
    );
  }
}

class _Client extends grpc.Client {
  _Client(super.channel);
  grpc.ResponseFuture<int> ping() => $createUnaryCall(
    grpc.ClientMethod<int, int>('/lan.Ping/Ping', _encode, _decode),
    7,
  );
}

const _peer = '192.168.66.94';
const _first = 'lan-11111111111111111111111111111111@dev';
const _second = 'lan-22222222222222222222222222222222@dev';

_Call _call(String peer, [String? principal]) {
  final call = _Call();
  when(() => call.remoteAddress).thenReturn(InternetAddress(peer));
  when(() => call.clientCertificate).thenReturn(null);
  when(() => call.clientMetadata).thenReturn(
    principal == null ? <String, String>{} : {'x-doso-dev-client': principal},
  );
  return call;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const A.init());
  });

  test(
    'private canonical IPv4 boundary rejects alternate and public forms',
    () {
      for (final value in [
        '10.1.2.3',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.66.64',
      ]) {
        expect(isPrivateLanIpv4(value), isTrue, reason: value);
      }
      for (final value in [
        '127.0.0.1',
        '0.0.0.0',
        '8.8.8.8',
        '172.15.0.1',
        '172.32.0.1',
        '192.169.0.1',
        '::ffff:192.168.66.94',
        'localhost',
        '192.168.066.94',
        '192.168.66.256',
        ' 192.168.66.94',
        '192.168.66.94\n',
      ]) {
        expect(isPrivateLanIpv4(value), isFalse, reason: value);
      }
    },
  );

  test('explicit LAN configuration skips retained TLS without enabling it', () {
    final config = _LanConfig();
    expect(config.validate(), isEmpty);
    expect(config.grpcMutualTlsEnabled, isFalse);
    expect(config.locomotionPrincipals, isEmpty);
    expect(
      grpcLanDevelopmentConfigurationErrors(
        transport: 'mtls',
        address: '',
        peers: const {},
      ),
      isEmpty,
    );
    expect(
      grpcMutualTlsConfigurationErrors(
        remotePeers: const {_peer},
        caFile: '',
        certificateFile: '',
        privateKeyFile: '',
        locomotionPrincipalCertificateFiles: const {},
      ),
      isNotEmpty,
    );
  });

  test(
    'LAN needs explicit mode, private bind and non-empty exact private peers',
    () {
      for (final entry in <(String, String, Set<String>)>[
        ('plaintext', '192.168.66.64', {_peer}),
        ('lan-dev', '0.0.0.0', {_peer}),
        ('lan-dev', '127.0.0.1', {_peer}),
        ('lan-dev', '192.168.66.64', {}),
        ('lan-dev', '192.168.66.64', {'8.8.8.8'}),
        ('lan-dev', '192.168.66.64', {'::ffff:192.168.66.94'}),
      ]) {
        expect(
          grpcLanDevelopmentConfigurationErrors(
            transport: entry.$1,
            address: entry.$2,
            peers: entry.$3,
          ),
          isNotEmpty,
        );
      }
    },
  );

  test(
    'all-RPC interceptor enforces exact peer even for read-only calls',
    () async {
      final interceptor = lanDevelopmentPeerInterceptor({_peer});
      final method = _Method();
      expect(await interceptor(_call(_peer), method), isNull);
      for (final peer in [
        '192.168.66.93',
        '127.0.0.1',
        '8.8.8.8',
        '::ffff:192.168.66.94',
      ]) {
        expect(await interceptor(_call(peer), method), isA<grpc.GrpcError>());
      }
      final absent = _Call();
      when(() => absent.remoteAddress).thenReturn(null);
      expect(await interceptor(absent, method), isA<grpc.GrpcError>());
    },
  );

  test(
    'development principal accepts only exact session labels from allowed peer',
    () {
      expect(lanDevelopmentPrincipal(_call(_peer, _first), {_peer}), _first);
      for (final principal in [
        null,
        '',
        'dev@robot',
        _first.toUpperCase(),
        'lan-1111@dev',
        '$_first, $_second',
        '$_first\n',
      ]) {
        expect(
          lanDevelopmentPrincipal(_call(_peer, principal), {_peer}),
          isNull,
        );
      }
      expect(
        lanDevelopmentPrincipal(_call('192.168.66.93', _first), {_peer}),
        isNull,
      );
    },
  );

  test(
    'real h2c listener enforces source interceptor before dispatch',
    () async {
      final addresses =
          (await NetworkInterface.list(type: InternetAddressType.IPv4))
              .expand((entry) => entry.addresses)
              .where((address) => isPrivateLanIpv4(address.address))
              .toList();
      if (addresses.isEmpty) {
        markTestSkipped('No private IPv4 interface for local h2c proof');
        return;
      }
      final address = addresses.first;
      final allowed = grpc.Server.create(
        services: [_Ping()],
        interceptors: [
          lanDevelopmentPeerInterceptor({address.address}),
        ],
      );
      await allowed.serve(address: address, port: 0);
      final channel = grpc.ClientChannel(
        address.address,
        port: allowed.port!,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      );
      try {
        expect(await _Client(channel).ping(), 7);
      } finally {
        await channel.shutdown();
        await allowed.shutdown();
      }
      final denied = grpc.Server.create(
        services: [_Ping()],
        interceptors: [lanDevelopmentPeerInterceptor({})],
      );
      await denied.serve(address: address, port: 0);
      final blocked = grpc.ClientChannel(
        address.address,
        port: denied.port!,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      );
      try {
        await expectLater(
          _Client(blocked).ping(),
          throwsA(
            isA<grpc.GrpcError>().having(
              (error) => error.code,
              'code',
              grpc.StatusCode.permissionDenied,
            ),
          ),
        );
      } finally {
        await blocked.shutdown();
        await denied.shutdown();
      }
    },
  );

  group('development mode preserves lease and actuator gates', () {
    late _Brain brain;
    late _Machine machine;
    late StreamController<History> history;
    late StreamSubscription<History> historySub;
    late ControlArbiter arbiter;
    late UnifiedCmsServer server;

    setUp(() {
      brain = _Brain();
      machine = _Machine();
      history = StreamController<History>();
      historySub = history.stream.listen((_) {});
      when(() => machine.state).thenReturn(Standing(historySub));
      when(() => machine.stream).thenAnswer((_) => const Stream<S>.empty());
      when(() => machine.isClosed).thenReturn(false);
      when(() => machine.isHandlingEvent).thenReturn(false);
      when(() => machine.profileSwitchInProgress).thenReturn(false);
      when(() => machine.commandVersion).thenReturn(0);
      when(() => machine.add(any())).thenReturn(null);
      when(() => brain.isModelLoaded).thenReturn(true);
      when(() => brain.standingPose).thenReturn(JointsMatrix.zero());
      arbiter = ControlArbiter(machine, timeout: const Duration(seconds: 1));
      server = UnifiedCmsServer(
        brain: brain,
        m: machine,
        mode: CmsMode.hardware,
        arbiter: arbiter,
        developmentPlaintext: true,
        hardwareMotionPeerAddresses: const {_peer},
        grpcLeaseTimeout: const Duration(milliseconds: 100),
      )..motorOutputEnabledProvider = () => true;
    });
    tearDown(() async {
      await server.dispose();
      arbiter.dispose();
      await historySub.cancel();
      await history.close();
    });

    test('metadata alone cannot activate default TLS mode', () async {
      final secure = UnifiedCmsServer(
        brain: brain,
        m: machine,
        mode: CmsMode.hardware,
        hardwareMotionPeerAddresses: const {_peer},
      )..motorOutputEnabledProvider = () => true;
      try {
        await expectLater(
          secure.acquireControl(
            _call(_peer, _first),
            proto.AcquireControlRequest(clientId: _first),
          ),
          throwsA(isA<grpc.GrpcError>()),
        );
      } finally {
        await secure.dispose();
      }
    });

    test(
      'missing metadata, wrong source and clientId mismatch remain rejected',
      () async {
        for (final call in [
          _call(_peer),
          _call('192.168.66.93', _first),
          _call(_peer, 'dev@robot'),
        ]) {
          await expectLater(
            server.acquireControl(
              call,
              proto.AcquireControlRequest(clientId: _first),
            ),
            throwsA(isA<grpc.GrpcError>()),
          );
        }
        await expectLater(
          server.acquireControl(
            _call(_peer, _first),
            proto.AcquireControlRequest(clientId: _second),
          ),
          throwsA(isA<grpc.GrpcError>()),
        );
        expect(arbiter.owner, isNull);
        verifyNever(() => machine.add(any()));
      },
    );

    test('owner, initial zero ACK and expiry remain enforced', () async {
      final call = _call(_peer, _first);
      final lease = await server.acquireControl(
        call,
        proto.AcquireControlRequest(clientId: _first),
      );
      expect(lease.accepted, isTrue);
      expect(lease.status.ownerId, _first);
      expect(lease.status.readyForWalk, isFalse);
      await expectLater(
        server.renewControlLease(
          _call(_peer, _second),
          proto.ControlLeaseRequest(token: lease.token),
        ),
        throwsA(isA<grpc.GrpcError>()),
      );
      final zero = proto.WalkRequest(
        token: lease.token,
        direction: proto.Vector3(x: 0, y: 0, z: 0),
      );
      zero.sequence = zero.sequence + 1;
      final ack = await server.walkChecked(call, zero);
      expect(ack.accepted, isTrue);
      expect(ack.status.readyForWalk, isTrue);
      clearInteractions(machine);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      final status = await server.getControlStatus(call, proto.Empty());
      expect(status.grpcLeaseActive, isFalse);
      expect(status.readyForWalk, isFalse);
      final stopped =
          verify(
                () => machine.add(captureAny(that: isA<CmdWalk>())),
              ).captured.single
              as CmdWalk;
      expect(stopped.direction, Vector3.zero());
    });

    test('no motor enable is implied by successful identity parsing', () async {
      server.motorOutputEnabledProvider = () => false;
      final lease = await server.acquireControl(
        _call(_peer, _first),
        proto.AcquireControlRequest(clientId: _first),
      );
      expect(lease.accepted, isFalse);
      expect(
        lease.reason,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTORS_DISABLED,
      );
      verifyNever(() => machine.add(any()));
    });

    test(
      'physical control priority remains above a valid development caller',
      () async {
        expect(arbiter.tryAcquire(ControlSource.yunzhuo), isTrue);
        final lease = await server.acquireControl(
          _call(_peer, _first),
          proto.AcquireControlRequest(clientId: _first),
        );
        expect(lease.accepted, isFalse);
        expect(
          lease.reason,
          proto.CommandRejectReason.COMMAND_REJECT_REASON_CONTROL_BUSY,
        );
        expect(arbiter.owner, ControlSource.yunzhuo);
      },
    );
  });
}
