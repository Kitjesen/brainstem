import 'package:han_dog/src/app/config.dart';
import 'package:han_dog/src/app/robot_profile.dart';
import 'package:han_dog/src/control_arbiter.dart';
import 'package:han_dog_brain/han_dog_brain.dart' show M, A;
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
        () => (history as List).add(
          (at: DateTime.now(), owner: null, reason: 'hack'),
        ),
        throwsUnsupportedError,
      );
    });

    test('yunzhuo preempts grpc', () {
      arbiter.command(const A.standUp(), ControlSource.grpc);
      expect(arbiter.owner, ControlSource.grpc);
      final accepted = arbiter.command(const A.standUp(), ControlSource.yunzhuo);
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
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('"name"'))),
      );
    });

    test('missing modelPath throws FormatException mentioning field', () {
      final json = validJson()..remove('modelPath');
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('"modelPath"'))),
      );
    });

    test('missing inferKp throws FormatException', () {
      final json = validJson()..remove('inferKp');
      expect(() => RobotProfile.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('inferKp with 15 elements throws FormatException mentioning length', () {
      final json = validJson()..['inferKp'] = List.filled(15, 0.0);
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('"inferKp"'), contains('16')),
        )),
      );
    });

    test('standingPose with wrong length throws FormatException', () {
      final json = validJson()..['standingPose'] = List.filled(8, 0.0);
      expect(
        () => RobotProfile.fromJson(json),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('"standingPose"'))),
      );
    });

    test('name with non-string type throws FormatException', () {
      final json = validJson()..['name'] = 42;
      expect(() => RobotProfile.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('optional numeric fields use defaults when absent', () {
      final profile = RobotProfile.fromJson(validJson());
      expect(profile.imuGyroscopeScale, closeTo(0.25, 1e-9));
      expect(profile.standUpCounts, 150);
      expect(profile.sitDownCounts, 150);
    });

    test('actionScale defaults to (0.125, 0.25, 0.25, 5.0) when absent', () {
      final profile = RobotProfile.fromJson(validJson());
      expect(profile.actionScale.$1, closeTo(0.125, 1e-9));
      expect(profile.actionScale.$2, closeTo(0.25, 1e-9));
      expect(profile.actionScale.$3, closeTo(0.25, 1e-9));
      expect(profile.actionScale.$4, closeTo(5.0, 1e-9));
    });

    test('jointVelocityScale defaults to (0.05, 0.05, 0.05, 0.05) when absent', () {
      final profile = RobotProfile.fromJson(validJson());
      expect(profile.jointVelocityScale.$1, closeTo(0.05, 1e-9));
      expect(profile.jointVelocityScale.$2, closeTo(0.05, 1e-9));
      expect(profile.jointVelocityScale.$3, closeTo(0.05, 1e-9));
      expect(profile.jointVelocityScale.$4, closeTo(0.05, 1e-9));
    });
  });
}
