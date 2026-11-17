import 'dart:io';
import 'package:thunder/src/app/config.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    final profiles = Directory('profiles');
    final created = !profiles.existsSync();
    if (created) profiles.createSync();
    addTearDown(() {
      if (created) profiles.deleteSync();
    });
  });
  group('ThunderConfig.validate', () {
    test('default config passes validation', () {
      expect(ThunderConfig().validate(), isEmpty);
    });

    test('isValid is true for default config', () {
      expect(ThunderConfig().isValid, isTrue);
    });

    test('toString includes all key fields', () {
      final s = ThunderConfig().toString();
      expect(s, contains('port='));
      expect(s, contains('imu='));
      expect(s, contains('profileDir='));
      expect(s, contains('startupTimeout='));
    });

    test('startupTimeoutSec defaults to 10', () {
      expect(ThunderConfig().startupTimeoutSec, 10);
    });

    test('startupTimeout Duration equals startupTimeoutSec seconds', () {
      final cfg = ThunderConfig();
      expect(cfg.startupTimeout, Duration(seconds: cfg.startupTimeoutSec));
    });

    test('gRPC motion lease defaults to 300 milliseconds', () {
      expect(
        ThunderConfig().grpcLeaseTimeout,
        const Duration(milliseconds: 300),
      );
    });

    test('motion lease must expire before an enabled arbiter timeout', () {
      expect(
        motionTimeoutsSafe(
          arbiterTimeout: Duration.zero,
          grpcLeaseTimeout: const Duration(seconds: 10),
        ),
        isTrue,
      );
      expect(
        motionTimeoutsSafe(
          arbiterTimeout: const Duration(seconds: 3),
          grpcLeaseTimeout: const Duration(milliseconds: 300),
        ),
        isTrue,
      );
      expect(
        motionTimeoutsSafe(
          arbiterTimeout: const Duration(milliseconds: 300),
          grpcLeaseTimeout: const Duration(milliseconds: 300),
        ),
        isFalse,
      );
      expect(
        motionTimeoutsSafe(
          arbiterTimeout: const Duration(milliseconds: 100),
          grpcLeaseTimeout: const Duration(milliseconds: 300),
        ),
        isFalse,
      );
    });

    test('motion peer allowlist accepts only explicit IP addresses', () {
      expect(parseGrpcMotionPeerAddresses('192.168.114.23, 10.0.0.8'), {
        '192.168.114.23',
        '10.0.0.8',
      });
      expect(
        () => parseGrpcMotionPeerAddresses('lingtu.local'),
        throwsFormatException,
      );
      expect(
        () => parseGrpcMotionPeerAddresses('0.0.0.0'),
        throwsFormatException,
      );
    });

    test('remote motion peers require a complete readable mTLS file set', () {
      final dir = Directory.systemTemp.createTempSync('thunder_mtls_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ca = File('${dir.path}${Platform.pathSeparator}ca.pem')
        ..writeAsStringSync('ca');
      final cert = File('${dir.path}${Platform.pathSeparator}server.pem')
        ..writeAsStringSync(
          '-----BEGIN CERTIFICATE-----\nAQID\n-----END CERTIFICATE-----\n',
        );
      final key = File('${dir.path}${Platform.pathSeparator}server.key')
        ..writeAsStringSync('key');

      expect(
        grpcMutualTlsConfigurationErrors(
          remotePeers: const <String>{},
          caFile: '',
          certificateFile: '',
          privateKeyFile: '',
          locomotionPrincipalCertificateFiles: const <String, String>{},
        ),
        isEmpty,
      );
      expect(
        grpcMutualTlsConfigurationErrors(
          remotePeers: const {'192.168.114.23'},
          caFile: '',
          certificateFile: '',
          privateKeyFile: '',
          locomotionPrincipalCertificateFiles: const <String, String>{},
        ),
        contains(
          allOf(
            contains('THUNDER_GRPC_ALLOWED_IPS'),
            contains('THUNDER_LINGTU_ALLOWED_IPS'),
          ),
        ),
      );
      expect(
        grpcMutualTlsConfigurationErrors(
          remotePeers: const {'192.168.114.23'},
          caFile: ca.path,
          certificateFile: cert.path,
          privateKeyFile: key.path,
          locomotionPrincipalCertificateFiles: {
            'lingtu-driver@sunrise': cert.path,
          },
        ),
        isEmpty,
      );
      expect(
        grpcMutualTlsConfigurationErrors(
          remotePeers: const {'192.168.114.23'},
          caFile: '${dir.path}${Platform.pathSeparator}missing-ca.pem',
          certificateFile: cert.path,
          privateKeyFile: key.path,
          locomotionPrincipalCertificateFiles: {
            'lingtu-driver@sunrise': cert.path,
          },
        ),
        contains(contains('THUNDER_GRPC_TLS_CLIENT_CA_FILE')),
      );
    });

    test('locomotion principals require strict unique mappings', () {
      expect(
        parseLocomotionPrincipalCertificateFiles(
          'lingtu-driver@sunrise=/etc/lingtu.crt,'
          'operator-console@field=/etc/operator.crt',
        ),
        {
          'lingtu-driver@sunrise': '/etc/lingtu.crt',
          'operator-console@field': '/etc/operator.crt',
        },
      );
      for (final invalid in <String>[
        'missing-separator',
        'LingTu@sunrise=/etc/client.crt',
        'lingtu-driver@sunrise=relative/client.crt',
        'lingtu-driver@sunrise=/etc/a.crt,lingtu-driver@sunrise=/etc/b.crt',
      ]) {
        expect(
          () => parseLocomotionPrincipalCertificateFiles(invalid),
          throwsFormatException,
        );
      }
    });
  });

  group('resolveGrpcAllowedIps', () {
    test('defaults to no remote peers when neither setting is present', () {
      expect(resolveGrpcAllowedIps(const {}), isEmpty);
    });

    test('accepts the generic setting and legacy setting independently', () {
      for (final key in <String>[
        'THUNDER_GRPC_ALLOWED_IPS',
        'THUNDER_LINGTU_ALLOWED_IPS',
      ]) {
        expect(resolveGrpcAllowedIps({key: '192.168.114.23, 10.0.0.8'}), {
          '192.168.114.23',
          '10.0.0.8',
        });
        expect(resolveGrpcAllowedIps({key: '  '}), isEmpty);
      }
    });

    test('accepts equivalent normalized sets in both settings', () {
      expect(
        resolveGrpcAllowedIps(const {
          'THUNDER_GRPC_ALLOWED_IPS': '192.168.114.23,10.0.0.8',
          'THUNDER_LINGTU_ALLOWED_IPS': ' 10.0.0.8, 192.168.114.23,10.0.0.8 ',
        }),
        {'192.168.114.23', '10.0.0.8'},
      );
      expect(
        resolveGrpcAllowedIps(const {
          'THUNDER_GRPC_ALLOWED_IPS': '2001:db8::1',
          'THUNDER_LINGTU_ALLOWED_IPS': '2001:0db8:0:0:0:0:0:1',
        }).length,
        1,
      );
      expect(
        resolveGrpcAllowedIps(const {
          'THUNDER_GRPC_ALLOWED_IPS': '',
          'THUNDER_LINGTU_ALLOWED_IPS': '  ',
        }),
        isEmpty,
      );
    });

    test('rejects conflicting sets instead of merging or overriding them', () {
      for (final settings in <Map<String, String>>[
        {
          'THUNDER_GRPC_ALLOWED_IPS': '10.0.0.8',
          'THUNDER_LINGTU_ALLOWED_IPS': '10.0.0.9',
        },
        {
          'THUNDER_GRPC_ALLOWED_IPS': '10.0.0.8',
          'THUNDER_LINGTU_ALLOWED_IPS': '10.0.0.8,10.0.0.9',
        },
        {
          'THUNDER_GRPC_ALLOWED_IPS': '',
          'THUNDER_LINGTU_ALLOWED_IPS': '10.0.0.8',
        },
        {
          'THUNDER_GRPC_ALLOWED_IPS': '10.0.0.8',
          'THUNDER_LINGTU_ALLOWED_IPS': '',
        },
      ]) {
        expect(
          () => resolveGrpcAllowedIps(settings),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('THUNDER_GRPC_ALLOWED_IPS'),
                contains('THUNDER_LINGTU_ALLOWED_IPS'),
              ),
            ),
          ),
        );
      }
    });

    test('rejects invalid addresses in either setting', () {
      for (final key in <String>[
        'THUNDER_GRPC_ALLOWED_IPS',
        'THUNDER_LINGTU_ALLOWED_IPS',
      ]) {
        for (final invalid in <String>[
          'client.local',
          '0.0.0.0',
          '::',
          '0:0:0:0:0:0:0:0',
          '10.0.0.8,',
        ]) {
          expect(
            () => resolveGrpcAllowedIps({key: invalid}),
            throwsFormatException,
          );
        }
      }
      expect(
        () => resolveGrpcAllowedIps(const {
          'THUNDER_GRPC_ALLOWED_IPS': '10.0.0.8',
          'THUNDER_LINGTU_ALLOWED_IPS': 'client.local',
        }),
        throwsFormatException,
      );
    });

    test('resolved peers cannot be modified', () {
      final peers = resolveGrpcAllowedIps(const {
        'THUNDER_GRPC_ALLOWED_IPS': '10.0.0.8',
      });
      expect(() => peers.add('10.0.0.9'), throwsUnsupportedError);
    });
  });
}
