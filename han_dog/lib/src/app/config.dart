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
  String get modelPath =>
      Platform.environment['HAN_DOG_MODEL'] ?? 'model/policy_260106.onnx';
  int get arbiterTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_ARBITER_TIMEOUT'] ?? '') ?? 3;
  int get sensorLowThreshold =>
      int.tryParse(
          Platform.environment['HAN_DOG_SENSOR_LOW_THRESHOLD'] ?? '') ??
      3;
  int get shutdownTimeoutSec =>
      int.tryParse(Platform.environment['HAN_DOG_SHUTDOWN_TIMEOUT'] ?? '') ?? 8;
  String get profileDir =>
      Platform.environment['HAN_DOG_PROFILE_DIR'] ?? 'profiles';
  bool get debugTui =>
      Platform.environment['HAN_DOG_DEBUG_TUI'] == 'true';

  Duration get arbiterTimeout => Duration(seconds: arbiterTimeoutSec);
  Duration get shutdownTimeout => Duration(seconds: shutdownTimeoutSec);

  @override
  String toString() => 'port=$grpcPort imu=$imuPort yunzhuo=$yunzhuoPort '
      'model=$modelPath arbiterTimeout=${arbiterTimeoutSec}s '
      'sensorLowThreshold=$sensorLowThreshold '
      'shutdownTimeout=${shutdownTimeoutSec}s';
}

/// 初始化 Logger，级别由 HAN_DOG_LOG 环境变量控制（默认 INFO）。
void setupLogging() {
  final levelName = Platform.environment['HAN_DOG_LOG'] ?? 'INFO';
  final level = Level.LEVELS.firstWhere(
    (l) => l.name == levelName.toUpperCase(),
    orElse: () => Level.INFO,
  );
  Logger.root.level = level;
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
  });
}

class SimpleBlocObserver extends BlocObserver {
  final Logger _log;
  SimpleBlocObserver(this._log);

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    _log.severe('BlocError ${bloc.runtimeType}: $error', error, stackTrace);
  }
}
