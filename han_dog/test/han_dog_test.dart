import 'dart:io';

import 'package:han_dog/src/app/config.dart';
import 'package:han_dog/src/app/robot_profile.dart';
import 'package:han_dog/src/control_arbiter.dart';
import 'package:han_dog_brain/han_dog_brain.dart'
    show A, BodyHeightObservationBuilder, M, StandardObservationBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart' show JointsMatrix;
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
    });

    test('legacy standingPose supplies both pose roles', () {
      final json = validJson()
        ..['standingPose'] = List.generate(16, (i) => i.toDouble());

      final profile = RobotProfile.fromJson(json);

      expect(profile.standUpPose.values, profile.standingPose.values);
      expect(profile.policyDefaultPose.values, profile.standingPose.values);
    });

    test('constructor defaults both pose roles to standingPose', () {
      final standingPose = JointsMatrix.fromList(
        List.generate(16, (i) => i.toDouble()),
      );
      final otherPose = JointsMatrix.zero();

      final profile = RobotProfile(
        name: 'constructor-test',
        modelPath: 'model.onnx',
        standingPose: standingPose,
        sittingPose: otherPose,
        inferKp: otherPose,
        inferKd: otherPose,
        standUpKp: otherPose,
        standUpKd: otherPose,
        sitDownKp: otherPose,
        sitDownKd: otherPose,
      );

      expect(profile.standUpPose.values, standingPose.values);
      expect(profile.policyDefaultPose.values, standingPose.values);
    });

    test('explicit stand-up and policy default poses remain independent', () {
      final json = validJson()
        ..['standingPose'] = List.filled(16, 1.0)
        ..['standUpPose'] = List.filled(16, 2.0)
        ..['policyDefaultPose'] = List.filled(16, 3.0);

      final profile = RobotProfile.fromJson(json);

      expect(profile.standingPose.values, List.filled(16, 1.0));
      expect(profile.standUpPose.values, List.filled(16, 2.0));
      expect(profile.policyDefaultPose.values, List.filled(16, 3.0));
    });

    test('observation builders use policyDefaultPose as their zero point', () {
      for (final observationType in ['standard', 'bodyHeight']) {
        final json = validJson()
          ..['observationType'] = observationType
          ..['standingPose'] = List.filled(16, 1.0)
          ..['standUpPose'] = List.filled(16, 2.0)
          ..['policyDefaultPose'] = List.filled(16, 3.0);

        final builder = RobotProfile.fromJson(json).toObservationBuilder();

        expect(
          builder.standingPose.values,
          List.filled(16, 3.0),
          reason: observationType,
        );
      }
    });

    test('split pose fields require exactly 16 finite numbers', () {
      for (final field in ['standUpPose', 'policyDefaultPose']) {
        final shortJson = validJson()..[field] = List.filled(15, 0.0);
        expect(
          () => RobotProfile.fromJson(shortJson),
          throwsFormatException,
          reason: '$field short length',
        );

        final nanJson = validJson()
          ..[field] = List.generate(16, (i) => i == 7 ? double.nan : 0.0);
        expect(
          () => RobotProfile.fromJson(nanJson),
          throwsFormatException,
          reason: '$field NaN',
        );
      }
    });

    test('description field defaults to empty string', () {
      expect(RobotProfile.fromJson(validJson()).description, '');
    });

    test('description field is read when present', () {
      final json = validJson()..['description'] = '标准行走';
      expect(RobotProfile.fromJson(json).description, '标准行走');
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
    });

    test('legacy profile defaults to the standard 57-dim observation', () {
      final profile = RobotProfile.fromJson(validJson());
      final builder = profile.toObservationBuilder();

      expect(profile.observationType, 'standard');
      expect(builder, isA<StandardObservationBuilder>());
      expect(builder.tensorSize, 57);
    });

    test('body-height fields build a 58-dim observation contract', () {
      final json = validJson()
        ..addAll({
          'observationType': 'bodyHeight',
          'inputName': 'policy_obs',
          'bodyHeightCommand': 0.42,
          'minBodyHeightCommand': 0.20,
          'maxBodyHeightCommand': 0.54,
          'velocityCommandMin': [-2.5, -1.0, -1.0],
          'velocityCommandMax': [2.5, 1.0, 1.0],
        });

      final profile = RobotProfile.fromJson(json);
      final builder = profile.toObservationBuilder();

      expect(profile.observationType, 'bodyHeight');
      expect(profile.inputName, 'policy_obs');
      expect(profile.bodyHeightCommand, 0.42);
      expect(profile.minBodyHeightCommand, 0.20);
      expect(profile.maxBodyHeightCommand, 0.54);
      expect(profile.velocityCommandMin, (-2.5, -1.0, -1.0));
      expect(profile.velocityCommandMax, (2.5, 1.0, 1.0));
      expect(builder, isA<BodyHeightObservationBuilder>());
      expect(builder.tensorSize, 58);
    });

    test('unknown observationType is rejected', () {
      final json = validJson()..['observationType'] = 'guessedFromShape';

      expect(
        () => RobotProfile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('observationType'), contains('guessedFromShape')),
          ),
        ),
      );
    });

    test('body-height minimum greater than maximum is rejected', () {
      final json = validJson()
        ..addAll({
          'observationType': 'bodyHeight',
          'minBodyHeightCommand': 0.55,
          'maxBodyHeightCommand': 0.20,
        });

      expect(() => RobotProfile.fromJson(json), throwsFormatException);
    });

    test('body-height default outside its range is rejected', () {
      final json = validJson()
        ..addAll({
          'observationType': 'bodyHeight',
          'bodyHeightCommand': 0.60,
          'minBodyHeightCommand': 0.20,
          'maxBodyHeightCommand': 0.54,
        });

      expect(() => RobotProfile.fromJson(json), throwsFormatException);
    });

    test('non-finite body-height fields are rejected', () {
      for (final field in [
        'bodyHeightCommand',
        'minBodyHeightCommand',
        'maxBodyHeightCommand',
      ]) {
        final json = validJson()
          ..addAll({'observationType': 'bodyHeight', field: double.nan});
        expect(
          () => RobotProfile.fromJson(json),
          throwsFormatException,
          reason: field,
        );
      }
    });

    test('inverted velocity command bounds are rejected', () {
      final json = validJson()
        ..['velocityCommandMin'] = [-2.5, 1.1, -1.0]
        ..['velocityCommandMax'] = [2.5, 1.0, 1.0];

      expect(() => RobotProfile.fromJson(json), throwsFormatException);
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
