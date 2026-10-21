import 'dart:io';

import 'package:han_dog/src/app/config.dart';
import 'package:han_dog/src/app/robot_profile.dart';
import 'package:han_dog/src/arm_teleop_protocol.dart';
import 'package:han_dog/src/control_arbiter.dart';
import 'package:han_dog_brain/han_dog_brain.dart'
    show A, M, ThunderFlatObservationBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockM extends Mock implements M {}

void main() {
  // ─── ControlArbiter ──────────────────────────────────────────

  group('ControlArbiter', () {
    late _MockM m;
    late ControlArbiter arbiter;

    setUp(() {
      m = _MockM();
      // ControlArbiter 只在 command() 内调用 m.add()，
      // 该方法为 void，mocktail 默认无需显式 stub。
      arbiter = ControlArbiter(m, timeout: const Duration(milliseconds: 100));
    });

    tearDown(() => arbiter.dispose());

    test('dispose is idempotent — second call does not throw', () {
      arbiter.dispose();
      expect(() => arbiter.dispose(), returnsNormally);
    });

    test('ownershipHistory starts empty', () {
      expect(arbiter.ownershipHistory, isEmpty);
    });

    test('ownershipHistory records acquire event', () {
      arbiter.command(const A.standUp(), ControlSource.grpc);
      expect(arbiter.ownershipHistory.length, 1);
      expect(arbiter.ownershipHistory.first.owner, ControlSource.grpc);
    });

    test('ownershipHistory records release on timeout', () async {
      arbiter.command(const A.standUp(), ControlSource.grpc);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(arbiter.ownershipHistory.length, greaterThanOrEqualTo(2));
      expect(arbiter.ownershipHistory.last.owner, isNull);
      expect(arbiter.ownershipHistory.last.reason, contains('timeout'));
    });

    test('ownershipHistory records manual release', () {
      arbiter.command(const A.standUp(), ControlSource.grpc);
      arbiter.release(ControlSource.grpc);
      expect(arbiter.ownershipHistory.length, 2);
      expect(arbiter.ownershipHistory.last.reason, contains('manual release'));
    });

    test('ownershipHistory capped at 20 entries', () {
      // 每次 yunzhuo 调用都被视为同一来源 → only first acquire is recorded,
      // 但超时后会 release → 用短 timeout 反复 acquire/release
      // 实际测法：直接验证上限不超 20
      for (var i = 0; i < 30; i++) {
        // 由于 yunzhuo 可以反复命令同一 source（不重复记录），
        // 先释放再重新获取才会产生新记录。
        arbiter.release(ControlSource.yunzhuo);
        arbiter.command(const A.standUp(), ControlSource.yunzhuo);
      }
      expect(arbiter.ownershipHistory.length, lessThanOrEqualTo(20));
    });

    test('ownershipHistory is unmodifiable', () {
      final history = arbiter.ownershipHistory;
      expect(
        () => (history as List).add((
          at: DateTime.now(),
          owner: null,
          reason: 'hack',
        )),
        throwsUnsupportedError,
      );
    });

    test('yunzhuo preempts grpc', () {
      arbiter.command(const A.standUp(), ControlSource.grpc);
      expect(arbiter.owner, ControlSource.grpc);
      final accepted = arbiter.command(
        const A.standUp(),
        ControlSource.yunzhuo,
      );
      expect(accepted, isTrue);
      expect(arbiter.owner, ControlSource.yunzhuo);
    });

    test('grpc cannot preempt yunzhuo', () {
      arbiter.command(const A.standUp(), ControlSource.yunzhuo);
      final accepted = arbiter.command(const A.standUp(), ControlSource.grpc);
      expect(accepted, isFalse);
      expect(arbiter.owner, ControlSource.yunzhuo);
    });
  });

  // ─── HanDogConfig.validate() ─────────────────────────────────

  group('HanDogConfig.validate', () {
    test('default config passes validation', () {
      expect(HanDogConfig().validate(), isEmpty);
    });

    test('isValid is true for default config', () {
      expect(HanDogConfig().isValid, isTrue);
    });

    test('toString includes all key fields', () {
      final s = HanDogConfig().toString();
      expect(s, contains('port='));
      expect(s, contains('imu='));
      expect(s, contains('profileDir='));
      expect(s, contains('startupTimeout='));
    });

    test('startupTimeoutSec defaults to 10', () {
      expect(HanDogConfig().startupTimeoutSec, 10);
    });

    test('startupTimeout Duration equals startupTimeoutSec seconds', () {
      final cfg = HanDogConfig();
      expect(cfg.startupTimeout, Duration(seconds: cfg.startupTimeoutSec));
    });
  });

  group('arm teleop secret resolution', () {
    const directSecret = '0123456789abcdef0123456789abcdef';

    test(
      'legacy direct environment value remains supported and is trimmed',
      () {
        expect(
          resolveArmTeleopSecret(
            environment: const {
              'HAN_DOG_ARM_TELEOP_SECRET': '  $directSecret\n',
            },
          ),
          directSecret,
        );
      },
    );

    test(
      'secret file takes precedence and is read exactly once per config',
      () {
        var reads = 0;
        final config = HanDogConfig(
          environment: const {
            'HAN_DOG_ARM_TELEOP_SECRET_FILE': '/secure/arm-teleop.key',
            'HAN_DOG_ARM_TELEOP_SECRET': 'must-not-be-used',
          },
          readTextFile: (path) {
            reads++;
            expect(path, '/secure/arm-teleop.key');
            return '\n$directSecret\n';
          },
        );

        expect(config.armTeleopSecret, directSecret);
        expect(config.armTeleopSecret, directSecret);
        expect(reads, 1);
      },
    );

    test('configured unreadable file fails closed without env fallback', () {
      var reads = 0;
      final config = HanDogConfig(
        environment: const {
          'HAN_DOG_ARM_TELEOP_SECRET_FILE': '/missing/arm-teleop.key',
          'HAN_DOG_ARM_TELEOP_SECRET': directSecret,
        },
        readTextFile: (path) {
          reads++;
          throw FileSystemException('denied', path);
        },
      );
      expect(() => config.armTeleopSecret, throwsA(isA<StateError>()));
      expect(() => config.armTeleopSecret, throwsA(isA<StateError>()));
      expect(reads, 1);
    });

    test('configured empty file fails closed', () {
      expect(
        () => resolveArmTeleopSecret(
          environment: const {
            'HAN_DOG_ARM_TELEOP_SECRET_FILE': '/secure/empty.key',
          },
          readTextFile: (_) => ' \n ',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('arm teleop profile selection', () {
    test('defaults to full gripper when both opt-in switches are absent', () {
      final config = HanDogConfig(environment: const {});
      expect(config.armTeleopActiveProfile, armTeleopProfileFullGripper);
    });

    test('six-axis-only requires both explicit true switches', () {
      final config = HanDogConfig(
        environment: const {
          'HAN_DOG_ARM_TELEOP_SIX_AXIS_ONLY': 'true',
          'HAN_DOG_ARM_TELEOP_ACKNOWLEDGE_GRIPPER_DISABLED': 'true',
        },
      );
      expect(config.armTeleopActiveProfile, armTeleopProfileSixAxisOnly);
      expect(config.validate(), isEmpty);
    });

    test('partial or malformed six-axis opt-in fails validation', () {
      final partial = HanDogConfig(
        environment: const {'HAN_DOG_ARM_TELEOP_SIX_AXIS_ONLY': 'true'},
      );
      expect(
        partial.validate(),
        contains(contains('must be configured together')),
      );

      final malformed = HanDogConfig(
        environment: const {
          'HAN_DOG_ARM_TELEOP_SIX_AXIS_ONLY': 'TRUE',
          'HAN_DOG_ARM_TELEOP_ACKNOWLEDGE_GRIPPER_DISABLED': 'TRUE',
        },
      );
      expect(malformed.validate(), isNotEmpty);
      expect(malformed.armTeleopActiveProfile, armTeleopProfileFullGripper);
    });
  });

  group('resolveProfileDir', () {
    test('prefers primary env var over legacy env var', () {
      expect(
        resolveProfileDir(
          primaryEnvVar: 'HAN_DOG_PROFILE_DIR',
          legacyEnvVars: const ['HAN_DOG_PROFILES_DIR'],
          environment: const {
            'HAN_DOG_PROFILE_DIR': '/primary/profiles',
            'HAN_DOG_PROFILES_DIR': '/legacy/profiles',
          },
        ),
        '/primary/profiles',
      );
    });

    test('accepts deployed legacy env var name', () {
      expect(
        resolveProfileDir(
          primaryEnvVar: 'HAN_DOG_PROFILE_DIR',
          legacyEnvVars: const ['HAN_DOG_PROFILES_DIR'],
          environment: const {'HAN_DOG_PROFILES_DIR': '/legacy/profiles'},
        ),
        '/legacy/profiles',
      );
    });

    test('falls back to han_dog/profiles when launched from repo root', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'brainstem_profile_dir',
      );
      final nestedProfiles = Directory(
        '${tempDir.path}${Platform.pathSeparator}han_dog'
        '${Platform.pathSeparator}profiles',
      )..createSync(recursive: true);
      try {
        expect(nestedProfiles.existsSync(), isTrue);
        expect(
          resolveProfileDir(
            primaryEnvVar: 'HAN_DOG_PROFILE_DIR',
            legacyEnvVars: const ['HAN_DOG_PROFILES_DIR'],
            environment: const {},
            workingDirectory: tempDir.path,
          ),
          'han_dog/profiles',
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  // ─── RobotProfile.fromJson() ─────────────────────────────────

  group('RobotProfile.fromJson', () {
    Map<String, dynamic> validJson() => {
      'name': 'test',
      'modelPath': 'model.onnx',
      'standingPose': List.filled(16, 0.0),
      'sittingPose': List.filled(16, 0.0),
      'inferKp': List.filled(16, 20.0),
      'inferKd': List.filled(16, 0.5),
      'standUpKp': List.filled(16, 30.0),
      'standUpKd': List.filled(16, 1.0),
      'sitDownKp': List.filled(16, 25.0),
      'sitDownKd': List.filled(16, 0.8),
    };

    test('valid JSON parses successfully', () {
      final profile = RobotProfile.fromJson(validJson());
      expect(profile.name, 'test');
      expect(profile.modelPath, 'model.onnx');
      expect(profile.description, '');
      expect(profile.standUpCounts, 150);
      expect(profile.observationLayout, 'standard57');
    });

    test('description field defaults to empty string', () {
      expect(RobotProfile.fromJson(validJson()).description, '');
    });

    test('description field is read when present', () {
      final json = validJson()..['description'] = '标准行走';
      expect(RobotProfile.fromJson(json).description, '标准行走');
    });

    test('thunderFlat53 observation layout selects the 53D builder', () {
      final json = validJson()..['observationLayout'] = 'thunderFlat53';
      final profile = RobotProfile.fromJson(json);
      expect(profile.observationLayout, 'thunderFlat53');
      expect(
        profile.toObservationBuilder(),
        isA<ThunderFlatObservationBuilder>(),
      );
      expect(profile.toObservationBuilder().tensorSize, 53);
    });

    test('unknown observation layout throws FormatException', () {
      final json = validJson()..['observationLayout'] = 'unknown';
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('observationLayout'),
          ),
        ),
      );
    });

    test('missing name throws FormatException mentioning field', () {
      final json = validJson()..remove('name');
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"name"'),
          ),
        ),
      );
    });

    test('missing modelPath throws FormatException mentioning field', () {
      final json = validJson()..remove('modelPath');
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"modelPath"'),
          ),
        ),
      );
    });

    test('missing inferKp throws FormatException', () {
      final json = validJson()..remove('inferKp');
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'inferKp with 15 elements throws FormatException mentioning length',
      () {
        final json = validJson()..['inferKp'] = List.filled(15, 0.0);
        expect(
          () => RobotProfile.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('"inferKp"'), contains('16')),
            ),
          ),
        );
      },
    );

    test('standingPose with wrong length throws FormatException', () {
      final json = validJson()..['standingPose'] = List.filled(8, 0.0);
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"standingPose"'),
          ),
        ),
      );
    });

    test('name with non-string type throws FormatException', () {
      final json = validJson()..['name'] = 42;
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('optional numeric fields use defaults when absent', () {
      final profile = RobotProfile.fromJson(validJson());
      expect(profile.imuGyroscopeScale, closeTo(0.25, 1e-9));
      expect(profile.standUpCounts, 150);
      expect(profile.sitDownCounts, 150);
      expect(profile.commandVxMax, 1.5);
      expect(profile.commandVyMax, 1.0);
      expect(profile.commandYawMax, 1.0);
      expect(profile.forwardMinCommand, 0.0);
      expect(profile.lateralMinCommand, 0.30);
      expect(profile.yawMinCommand, 0.40);
    });

    test('command envelope fields are read when present', () {
      final json = validJson()
        ..['commandVxMax'] = 0.5
        ..['commandVyMax'] = 0.4
        ..['commandYawMax'] = 0.25
        ..['forwardMinCommand'] = 0.1
        ..['lateralMinCommand'] = 0.2
        ..['yawMinCommand'] = 0.3;
      final profile = RobotProfile.fromJson(json);
      expect(profile.commandVxMax, 0.5);
      expect(profile.commandVyMax, 0.4);
      expect(profile.commandYawMax, 0.25);
      expect(profile.forwardMinCommand, 0.1);
      expect(profile.lateralMinCommand, 0.2);
      expect(profile.yawMinCommand, 0.3);
    });

    test('invalid command envelope fields throw FormatException', () {
      expect(
        () => RobotProfile.fromJson(validJson()..['commandVxMax'] = 0),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RobotProfile.fromJson(validJson()..['lateralMinCommand'] = 1.01),
        throwsA(isA<FormatException>()),
      );
    });

    test('actionScale defaults to (0.125, 0.25, 0.25, 5.0) when absent', () {
      final profile = RobotProfile.fromJson(validJson());
      expect(profile.actionScale.$1, closeTo(0.125, 1e-9));
      expect(profile.actionScale.$2, closeTo(0.25, 1e-9));
      expect(profile.actionScale.$3, closeTo(0.25, 1e-9));
      expect(profile.actionScale.$4, closeTo(5.0, 1e-9));
    });

    test('NaN in inferKp array throws FormatException', () {
      final json = validJson()
        ..['inferKp'] = List.generate(16, (i) => i == 0 ? double.nan : 1.0);
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('non-finite'),
          ),
        ),
      );
    });

    test('null element in inferKd array throws FormatException', () {
      final json = validJson()
        ..['inferKd'] = List.generate(16, (i) => i == 3 ? null : 1.0);
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('must be a number'),
          ),
        ),
      );
    });

    test('NaN imuGyroscopeScale throws FormatException', () {
      final json = validJson()..['imuGyroscopeScale'] = double.nan;
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('finite'),
          ),
        ),
      );
    });

    test(
      'jointVelocityScale defaults to (0.05, 0.05, 0.05, 0.05) when absent',
      () {
        final profile = RobotProfile.fromJson(validJson());
        expect(profile.jointVelocityScale.$1, closeTo(0.05, 1e-9));
        expect(profile.jointVelocityScale.$2, closeTo(0.05, 1e-9));
        expect(profile.jointVelocityScale.$3, closeTo(0.05, 1e-9));
        expect(profile.jointVelocityScale.$4, closeTo(0.05, 1e-9));
      },
    );
  });
}
