import 'dart:io';

import 'package:cms/cms.dart';
import 'package:logging/logging.dart';

import '../arm_teleop_protocol.dart';

const _defaultProfileDirCandidates = <String>['profiles', 'han_dog/profiles'];

/// 解析策略目录。
///
/// 优先级：
/// 1. [primaryEnvVar]
/// 2. [legacyEnvVars]
/// 3. 默认候选目录（先 `profiles/`，再 `han_dog/profiles/`）
String resolveProfileDir({
  required String primaryEnvVar,
  List<String> legacyEnvVars = const [],
  Map<String, String>? environment,
  String? workingDirectory,
}) {
  final env = environment ?? Platform.environment;
  for (final key in <String>[primaryEnvVar, ...legacyEnvVars]) {
    final value = env[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  for (final candidate in _defaultProfileDirCandidates) {
    if (_directoryExists(candidate, workingDirectory: workingDirectory)) {
      return candidate;
    }
  }
  return _defaultProfileDirCandidates.first;
}

bool _directoryExists(String path, {String? workingDirectory}) {
  final dir = Directory(path);
  if (dir.isAbsolute || workingDirectory == null) {
    return dir.existsSync();
  }
  return Directory(_joinPath(workingDirectory, path)).existsSync();
}

String _joinPath(String base, String child) {
  final trimmedBase = base.endsWith(Platform.pathSeparator)
      ? base.substring(0, base.length - 1)
      : base;
  final normalizedChild = child
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.isNotEmpty)
      .join(Platform.pathSeparator);
  if (normalizedChild.isEmpty) {
    return trimmedBase;
  }
  return '$trimmedBase${Platform.pathSeparator}$normalizedChild';
}

/// Resolves the arm-teleop HMAC secret without exposing it through systemd's
/// service environment. A configured file always takes precedence over the
/// legacy direct environment variable and is never allowed to fall back when
/// it is missing, unreadable, or empty.
String resolveArmTeleopSecret({
  Map<String, String>? environment,
  String Function(String path)? readTextFile,
}) {
  final env = environment ?? Platform.environment;
  final secretFile = env['HAN_DOG_ARM_TELEOP_SECRET_FILE']?.trim();
  if (secretFile != null && secretFile.isNotEmpty) {
    final reader = readTextFile ?? (path) => File(path).readAsStringSync();
    try {
      final secret = reader(secretFile).trim();
      if (secret.isEmpty) {
        throw StateError('arm-teleop secret file is empty: $secretFile');
      }
      return secret;
    } catch (error) {
      if (error is StateError) rethrow;
      throw StateError(
        'cannot read arm-teleop secret file "$secretFile": $error',
      );
    }
  }
  return env['HAN_DOG_ARM_TELEOP_SECRET']?.trim() ?? '';
}

/// 从环境变量读取配置，每个都有合理的默认值。
class HanDogConfig {
  final Map<String, String> _armTeleopEnvironment;
  final String Function(String path)? _armTeleopFileReader;
  bool _armTeleopSecretResolved = false;
  String? _resolvedArmTeleopSecret;
  Object? _armTeleopSecretError;
  StackTrace? _armTeleopSecretStackTrace;

  HanDogConfig({
    Map<String, String>? environment,
    String Function(String path)? readTextFile,
  }) : _armTeleopEnvironment = environment ?? Platform.environment,
       _armTeleopFileReader = readTextFile;

  int get grpcPort =>
      int.tryParse(Platform.environment['HAN_DOG_PORT'] ?? '') ?? 13145;
  String get imuPort =>
      Platform.environment['HAN_DOG_IMU_PORT'] ?? '/dev/ttyUSB1';
  String get yunzhuoPort =>
      Platform.environment['HAN_DOG_YUNZHUO_PORT'] ?? '/dev/yunzhuo';
  String get xboxDevice =>
      Platform.environment['HAN_DOG_XBOX_DEVICE'] ?? '/dev/input/js0';
  String get nc500HidrawDevice =>
      Platform.environment['HAN_DOG_NC500_HIDRAW_DEVICE'] ?? '/dev/hidraw0';
  String get xboxConfigPath =>
      Platform.environment['HAN_DOG_XBOX_CONFIG'] ?? 'han_dog/config/xbox.json';

  /// 机械臂 UDP 桥接默认关闭；必须显式启用并提供受限权限的密钥文件。
  bool get armTeleopEnabled =>
      _armTeleopEnvironment['HAN_DOG_ARM_TELEOP_ENABLED'] == 'true';
  String get armTeleopHost =>
      _armTeleopEnvironment['HAN_DOG_ARM_TELEOP_HOST'] ?? '192.168.66.65';
  int get armTeleopControlPort =>
      int.tryParse(
        _armTeleopEnvironment['HAN_DOG_ARM_TELEOP_CONTROL_PORT'] ?? '',
      ) ??
      14600;
  int get armTeleopAckPort =>
      int.tryParse(
        _armTeleopEnvironment['HAN_DOG_ARM_TELEOP_ACK_PORT'] ?? '',
      ) ??
      14601;
  bool get armTeleopSixAxisOnly =>
      _armTeleopEnvironment['HAN_DOG_ARM_TELEOP_SIX_AXIS_ONLY']?.trim() ==
          'true' &&
      _armTeleopEnvironment['HAN_DOG_ARM_TELEOP_ACKNOWLEDGE_GRIPPER_DISABLED']
              ?.trim() ==
          'true';
  String get armTeleopActiveProfile => armTeleopSixAxisOnly
      ? armTeleopProfileSixAxisOnly
      : armTeleopProfileFullGripper;
  String get armTeleopSecret {
    if (!_armTeleopSecretResolved) {
      _armTeleopSecretResolved = true;
      try {
        _resolvedArmTeleopSecret = resolveArmTeleopSecret(
          environment: _armTeleopEnvironment,
          readTextFile: _armTeleopFileReader,
        );
      } catch (error, stackTrace) {
        _armTeleopSecretError = error;
        _armTeleopSecretStackTrace = stackTrace;
      }
    }
    final error = _armTeleopSecretError;
    if (error != null) {
      Error.throwWithStackTrace(error, _armTeleopSecretStackTrace!);
    }
    return _resolvedArmTeleopSecret!;
  }

  /// 默认策略名称（对应 profileDir 中的 JSON 文件 name 字段）。
  /// 未设置时使用加载顺序第一个策略。
  String? get defaultProfile => Platform.environment['HAN_DOG_DEFAULT_PROFILE'];
  int get arbiterTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_ARBITER_TIMEOUT'] ?? '') ?? 3;
  int get sensorLowThreshold =>
      int.tryParse(
        Platform.environment['HAN_DOG_SENSOR_LOW_THRESHOLD'] ?? '',
      ) ??
      3;
  int get shutdownTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_SHUTDOWN_TIMEOUT'] ?? '') ?? 8;
  int get startupTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_STARTUP_TIMEOUT'] ?? '') ?? 10;

  /// 关节位置安全限位（绝对值，rad）。任一关节超过此值立即触发 Fault。
  /// 默认 3.14 rad（π，物理不可能超过），设置更小值可提供提前保护。
  double get jointLimitRad =>
      double.tryParse(Platform.environment['HAN_DOG_JOINT_LIMIT_RAD'] ?? '') ??
      3.14;
  String get profileDir => resolveProfileDir(
    primaryEnvVar: 'HAN_DOG_PROFILE_DIR',
    legacyEnvVars: const ['HAN_DOG_PROFILES_DIR'],
  );

  /// 日志目录（默认 'logs'，空字符串禁用文件日志）。
  String get logDir => Platform.environment['HAN_DOG_LOG_DIR'] ?? 'logs';
  bool get debugTui => Platform.environment['HAN_DOG_DEBUG_TUI'] == 'true';

  Duration get arbiterTimeout => Duration(seconds: arbiterTimeoutSec);
  Duration get shutdownTimeout => Duration(seconds: shutdownTimeoutSec);
  Duration get startupTimeout => Duration(seconds: startupTimeoutSec);

  /// 校验配置有效性，返回所有错误描述列表。空列表表示配置合法。
  List<String> validate() {
    final errors = <String>[];
    if (grpcPort < 1 || grpcPort > 65535) {
      errors.add('HAN_DOG_PORT=$grpcPort 超出范围 [1-65535]');
    }
    if (arbiterTimeoutSec < 0 || arbiterTimeoutSec > 3600) {
      errors.add(
        'HAN_DOG_ARBITER_TIMEOUT=${arbiterTimeoutSec}s 需在 [0, 3600] 范围内（0=永不释放）',
      );
    }
    if (shutdownTimeoutSec < 1 || shutdownTimeoutSec > 300) {
      errors.add(
        'HAN_DOG_SHUTDOWN_TIMEOUT=${shutdownTimeoutSec}s 需在 [1, 300] 范围内',
      );
    }
    if (startupTimeoutSec < 1 || startupTimeoutSec > 300) {
      errors.add(
        'HAN_DOG_STARTUP_TIMEOUT=${startupTimeoutSec}s 需在 [1, 300] 范围内',
      );
    }
    if (jointLimitRad <= 0 || !jointLimitRad.isFinite) {
      errors.add('HAN_DOG_JOINT_LIMIT_RAD=$jointLimitRad 必须为有限正数');
    }
    if (sensorLowThreshold < 1) {
      errors.add('HAN_DOG_SENSOR_LOW_THRESHOLD=$sensorLowThreshold 至少需 1');
    }
    if (!_directoryExists(profileDir)) {
      errors.add('HAN_DOG_PROFILE_DIR="$profileDir" 目录不存在');
    }
    _validateArmTeleopProfileSwitches(errors);
    return errors;
  }

  void _validateArmTeleopProfileSwitches(List<String> errors) {
    const sixAxisKey = 'HAN_DOG_ARM_TELEOP_SIX_AXIS_ONLY';
    const acknowledgeKey = 'HAN_DOG_ARM_TELEOP_ACKNOWLEDGE_GRIPPER_DISABLED';
    final sixAxisPresent = _armTeleopEnvironment.containsKey(sixAxisKey);
    final acknowledgePresent = _armTeleopEnvironment.containsKey(
      acknowledgeKey,
    );
    final sixAxisValue = _armTeleopEnvironment[sixAxisKey]?.trim();
    final acknowledgeValue = _armTeleopEnvironment[acknowledgeKey]?.trim();

    for (final entry in <MapEntry<String, String?>>[
      MapEntry(sixAxisKey, sixAxisValue),
      MapEntry(acknowledgeKey, acknowledgeValue),
    ]) {
      if (entry.value != null &&
          entry.value != 'true' &&
          entry.value != 'false') {
        errors.add('${entry.key} must be exactly true or false');
      }
    }
    if (sixAxisPresent != acknowledgePresent) {
      errors.add('$sixAxisKey and $acknowledgeKey must be configured together');
    } else if (sixAxisPresent && sixAxisValue != acknowledgeValue) {
      errors.add('$sixAxisKey and $acknowledgeKey must have the same value');
    }
  }

  /// 配置是否合法。
  bool get isValid => validate().isEmpty;

  @override
  String toString() =>
      'port=$grpcPort imu=$imuPort yunzhuo=$yunzhuoPort '
      'profileDir=$profileDir '
      '${defaultProfile != null ? "defaultProfile=$defaultProfile " : ""}'
      'arbiterTimeout=${arbiterTimeoutSec}s '
      'sensorLowThreshold=$sensorLowThreshold '
      'shutdownTimeout=${shutdownTimeoutSec}s '
      'startupTimeout=${startupTimeoutSec}s '
      'jointLimitRad=$jointLimitRad '
      'logDir=$logDir debugTui=$debugTui';
}

/// 初始化 Logger，级别由 HAN_DOG_LOG 环境变量控制（默认 INFO）。
///
/// [logDir] 非空时，同时写入每日轮转日志文件（han_dog_YYYYMMDD.log）。
/// 启动时自动删除 7 天前的旧日志文件。
void setupLogging({String logDir = ''}) {
  final levelName = Platform.environment['HAN_DOG_LOG'] ?? 'INFO';
  final level = Level.LEVELS.firstWhere(
    (l) => l.name == levelName.toUpperCase(),
    orElse: () => Level.INFO,
  );
  Logger.root.level = level;

  RandomAccessFile? logFile;
  if (logDir.isNotEmpty) {
    try {
      final dir = Directory(logDir);
      dir.createSync(recursive: true);
      _cleanOldLogs(dir);
      final now = DateTime.now();
      final dateStr =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      logFile = File(
        '$logDir${Platform.pathSeparator}han_dog_$dateStr.log',
      ).openSync(mode: FileMode.append);
    } catch (e) {
      stderr.writeln('setupLogging: cannot open log file in $logDir: $e');
    }
  }

  Logger.root.onRecord.listen((r) {
    final prefix =
        '${r.time.toIso8601String()} ${r.level.name.padRight(7)} ${r.loggerName}';
    if (r.level >= Level.WARNING) {
      stderr.writeln('$prefix: ${r.message}');
      if (r.error != null) stderr.writeln('  error: ${r.error}');
      if (r.stackTrace != null) stderr.writeln('  ${r.stackTrace}');
    } else {
      stdout.writeln('$prefix: ${r.message}');
    }
    if (logFile != null) {
      try {
        logFile.writeStringSync('$prefix: ${r.message}\n');
        if (r.error != null) logFile.writeStringSync('  error: ${r.error}\n');
        if (r.stackTrace != null) {
          logFile.writeStringSync('  ${r.stackTrace}\n');
        }
      } catch (_) {}
    }
  });
}

/// 删除 [dir] 中超过 7 天的 han_dog_*.log 文件。
void _cleanOldLogs(Directory dir) {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  try {
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('han_dog_') || !name.endsWith('.log')) continue;
      if (entity.statSync().modified.isBefore(cutoff)) {
        entity.deleteSync();
      }
    }
  } catch (_) {}
}

class SimpleBlocObserver extends BlocObserver {
  final Logger _log;
  SimpleBlocObserver(this._log);

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    _log.severe('BlocError ${bloc.runtimeType}: $error', error, stackTrace);
  }
}
