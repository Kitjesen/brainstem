import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:thunder/src/server/grpc_tls.dart';
import 'package:test/test.dart';

final _opensslAvailable = () {
  try {
    return Process.runSync('openssl', const ['version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}();

List<int> _encodeInt(int value) => <int>[value];
int _decodeInt(List<int> value) => value.single;

final class _PingService extends grpc.Service {
  @override
  String get $name => 'test.Ping';

  _PingService() {
    $addMethod(
      grpc.ServiceMethod<int, int>(
        'Ping',
        _ping,
        false,
        false,
        _decodeInt,
        _encodeInt,
      ),
    );
  }

  Future<int> _ping(grpc.ServiceCall call, Future<int> request) => request;
}

final class _PingClient extends grpc.Client {
  static final _pingMethod = grpc.ClientMethod<int, int>(
    '/test.Ping/Ping',
    _encodeInt,
    _decodeInt,
  );

  _PingClient(super.channel);

  grpc.ResponseFuture<int> ping(int value, {grpc.CallOptions? options}) =>
      $createUnaryCall(_pingMethod, value, options: options);
}

final class _SecurityContextChannelCredentials extends grpc.ChannelCredentials {
  final SecurityContext _context;

  _SecurityContextChannelCredentials(this._context) : super.secure();

  @override
  SecurityContext get securityContext => _context;
}

void main() {
  test(
    'Brainstem TLS listener requires a trusted client certificate',
    () async {
      final directory = Directory.systemTemp.createTempSync('brainstem_tls_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final certificate = '${directory.path}${Platform.pathSeparator}peer.crt';
      final privateKey = '${directory.path}${Platform.pathSeparator}peer.key';
      final opensslConfig = File(
        '${directory.path}${Platform.pathSeparator}openssl.cnf',
      )..writeAsStringSync('[req]\ndistinguished_name=dn\n[dn]\n');
      final generated = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-config',
        opensslConfig.path,
        '-days',
        '1',
        '-subj',
        '/CN=localhost',
        '-addext',
        'subjectAltName=DNS:localhost,IP:127.0.0.1',
        '-keyout',
        privateKey,
        '-out',
        certificate,
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());

      final server = grpc.Server.create(services: [_PingService()]);
      await server.serve(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        security: MutualTlsServerCredentials(
          certificateFile: certificate,
          privateKeyFile: privateKey,
          clientCaFile: certificate,
        ),
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      addTearDown(server.shutdown);

      final unauthenticatedChannel = grpc.ClientChannel(
        'localhost',
        port: server.port!,
        options: grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.secure(
            certificates: File(certificate).readAsBytesSync(),
          ),
        ),
      );
      final unauthenticatedClient = _PingClient(unauthenticatedChannel);
      await expectLater(
        unauthenticatedClient.ping(
          1,
          options: grpc.CallOptions(timeout: const Duration(milliseconds: 500)),
        ),
        throwsA(isA<grpc.GrpcError>()),
      );
      await unauthenticatedChannel.shutdown();

      final rogueCertificate =
          '${directory.path}${Platform.pathSeparator}rogue.crt';
      final rogueKey = '${directory.path}${Platform.pathSeparator}rogue.key';
      final rogueGenerated = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-config',
        opensslConfig.path,
        '-days',
        '1',
        '-subj',
        '/CN=localhost',
        '-keyout',
        rogueKey,
        '-out',
        rogueCertificate,
      ]);
      expect(
        rogueGenerated.exitCode,
        0,
        reason: rogueGenerated.stderr.toString(),
      );
      final rogueContext = grpc.createSecurityContext(false)
        ..setTrustedCertificates(certificate)
        ..useCertificateChain(rogueCertificate)
        ..usePrivateKey(rogueKey);
      final rogueChannel = grpc.ClientChannel(
        'localhost',
        port: server.port!,
        options: grpc.ChannelOptions(
          credentials: _SecurityContextChannelCredentials(rogueContext),
        ),
      );
      await expectLater(
        _PingClient(rogueChannel).ping(
          2,
          options: grpc.CallOptions(timeout: const Duration(milliseconds: 500)),
        ),
        throwsA(isA<grpc.GrpcError>()),
      );
      await rogueChannel.shutdown();

      final authenticated = grpc.createSecurityContext(false)
        ..setTrustedCertificates(certificate)
        ..useCertificateChain(certificate)
        ..usePrivateKey(privateKey);
      final authenticatedChannel = grpc.ClientChannel(
        'localhost',
        port: server.port!,
        options: grpc.ChannelOptions(
          credentials: _SecurityContextChannelCredentials(authenticated),
        ),
      );
      final authenticatedClient = _PingClient(authenticatedChannel);
      expect(await authenticatedClient.ping(7), 7);
      await authenticatedChannel.shutdown();
    },
    skip: !_opensslAvailable ? 'openssl is required for TLS fixtures' : false,
  );
}
