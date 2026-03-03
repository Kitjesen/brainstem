import 'dart:io';

import 'package:cms/cms.dart';
import 'package:logging/logging.dart';

/// 从环境变量读取配置，每个都有合理的默认值。
class HanDogConfig {
  int get grpcPort =>
      int.tryParse(Platform.environment['HAN_DOG_PORT'] ?? '') ?? 13145;
  String get imuPort =>
      Platform.environment['HAN_DOG_IMU_PORT'] ?? '/dev/ttyUSB1';
  String get yunzhuoPort =>
      Platform.environment['HAN_DOG_YUNZHUO_PORT'] ?? '/dev/yunzhuo';
  /// 默认策略名称（对应 profileDir 中的 JSON 文件 name 字段）。
  /// 未设置时使用加载顺序第一个策略。
  String? get defaultProfile => Platform.environment['HAN_DOG_DEFAULT_PROFILE'];
  int get arbiterTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_ARBITER_TIMEOUT'] ?? '') ?? 3;
  int get sensorLowThreshold =>
      int.tryParse(
          Platform.environment['HAN_DOG_SENSOR_LOW_THRESHOLD'] ?? '') ??
      3;
  int get shutdownTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_SHUTDOWN_TIMEOUT'] ?? '') ?? 8;
  int get startupTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_STARTUP_TIMEOUT'] ?? '') ?? 10;
  /// 关节位置安全限位（绝对值，rad）。任一关节超过此值立即触发 Fault。
  /// 默认 3.14 rad（π，物理不可能超过），设置更小值可提供提前保护。
  double get jointLimitRad =>
      double.tryParse(Platform.environment['HAN_DOG_JOINT_LIMIT_RAD'] ?? '') ?? 3.14;
  String get profileDir =>
      Platform.environment['HAN_DOG_PROFILE_DIR'] ?? 'profiles';
  /// 日志目录（默认 'logs'，空字符串禁用文件日志）。
  String get logDir =>
      Platform.environment['HAN_DOG_LOG_DIR'] ?? 'logs';
  bool get debugTui =>
      Platform.environment['HAN_DOG_DEBUG_TUI'] == 'true';

  Duration get arbiterTimeout => Duration(seconds: arbiterTimeoutSec);
  Duration get shutdownTimeout => Duration(seconds: shutdownTimeoutSec);
  Duration get startupTimeout => Duration(seconds: startupTimeoutSec);

  /// 校验配置有效性，返回所有错误描述列表。空列表表示配置合法。
  List<String> validate() {
    final errors = <String>[];
    if (grpcPort < 1 || grpcPort > 65535) {
      errors.add('HAN_DOG_PORT=$grpcPort 超出范围 [1-65535]');
    }
    if (arbiterTimeoutSec < 1) {
      errors.add('HAN_DOG_ARBITER_TIMEOUT=${arbiterTimeoutSec}s 至少需 1s');
    }
    if (shutdownTimeoutSec < 1) {
      errors.add('HAN_DOG_SHUTDOWN_TIMEOUT=${shutdownTimeoutSec}s 至少需 1s');
    }
    if (startupTimeoutSec < 1) {
      errors.add('HAN_DOG_STARTUP_TIMEOUT=${startupTimeoutSec}s 至少需 1s');
    }
    if (jointLimitRad <= 0) {
      errors.add('HAN_DOG_JOINT_LIMIT_RAD=$jointLimitRad 必须为正数');
    }
    if (sensorLowThreshold < 1) {
      errors.add('HAN_DOG_SENSOR_LOW_THRESHOLD=$sensorLowThreshold 至少需 1');
    }
    return errors;
  }

  /// 配置是否合法。
  bool get isValid => validate().isEmpty;

  @override
  String toString() => 'port=$grpcPort imu=$imuPort yunzhuo=$yunzhuoPort '
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
      final dateStr = '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      logFile = File('$logDir${Platform.pathSeparator}han_dog_$dateStr.log')
          .openSync(mode: FileMode.append);
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
