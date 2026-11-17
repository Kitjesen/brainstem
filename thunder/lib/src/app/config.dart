import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cms/cms.dart';
import 'package:logging/logging.dart';

import '../server/grpc_lan_development.dart';

import '../arm_teleop_protocol.dart';

const _defaultProfileDirCandidates = <String>['profiles', 'thunder/profiles'];

const _grpcAllowedIpsSettings =
    'THUNDER_GRPC_ALLOWED_IPS (legacy: THUNDER_LINGTU_ALLOWED_IPS)';

/// Parse the exact source IPs allowed to use lease-aware gRPC motion RPCs.
///
/// Hostnames and wildcard addresses are rejected so the hardware boundary does
/// not silently expand through DNS or an accidental bind-all value.
Set<String> parseGrpcMotionPeerAddresses(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <String>{};
  }
  final peers = <String>{};
  for (final entry in raw.split(',')) {
    final value = entry.trim();
    final parsed = InternetAddress.tryParse(value);
    if (parsed == null) {
      throw FormatException('invalid literal IP address: "$value"');
    }
    final address = InternetAddress.fromRawAddress(parsed.rawAddress);
    if (address.address == InternetAddress.anyIPv4.address ||
        address.address == InternetAddress.anyIPv6.address) {
      throw FormatException('wildcard address is not allowed: "$value"');
    }
    peers.add(address.address);
  }
  return Set<String>.unmodifiable(peers);
}

/// Resolve the generic allowlist and its legacy alias without widening access.
/// Both settings, when present, must describe the same normalized IP set.
Set<String> resolveGrpcAllowedIps(Map<String, String> environment) {
  final primary = environment['THUNDER_GRPC_ALLOWED_IPS'];
  final legacy = environment['THUNDER_LINGTU_ALLOWED_IPS'];
  final primaryPeers = parseGrpcMotionPeerAddresses(primary);
  final legacyPeers = parseGrpcMotionPeerAddresses(legacy);
  if (primary != null &&
      legacy != null &&
      (primaryPeers.length != legacyPeers.length ||
          !primaryPeers.containsAll(legacyPeers))) {
    throw const FormatException(
      'THUNDER_GRPC_ALLOWED_IPS and legacy THUNDER_LINGTU_ALLOWED_IPS '
      'must contain the same IP addresses when both are set',
    );
  }
  return primary != null ? primaryPeers : legacyPeers;
}

final _principalPattern = RegExp(r'^[a-z][a-z0-9-]*@[a-z][a-z0-9-]*$');

Map<String, String> parseLocomotionPrincipalCertificateFiles(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String, String>{};
  final principals = <String, String>{};
  for (final entry in raw.split(',')) {
    final separator = entry.indexOf('=');
    if (separator <= 0 || separator == entry.length - 1) {
      throw FormatException(
        'expected principal=/absolute/certificate.pem: "$entry"',
      );
    }
    final principal = entry.substring(0, separator).trim();
    final path = entry.substring(separator + 1).trim();
    if (!_principalPattern.hasMatch(principal)) {
      throw FormatException('invalid principal: "$principal"');
    }
    if (!path.startsWith('/') || path.contains(RegExp(r'[\r\n]'))) {
      throw FormatException('certificate path must be absolute: "$path"');
    }
    if (principals.containsKey(principal)) {
      throw FormatException('duplicate principal: "$principal"');
    }
    principals[principal] = path;
  }
  return Map<String, String>.unmodifiable(principals);
}

/// The gRPC lease deadman must fire before ownership can time out.
///
/// A zero arbiter timeout disables ownership expiry. Otherwise equality is
/// unsafe because the arbiter timer is armed before the lease timer.
bool motionTimeoutsSafe({
  required Duration arbiterTimeout,
  required Duration grpcLeaseTimeout,
}) => arbiterTimeout == Duration.zero || grpcLeaseTimeout < arbiterTimeout;

List<String> grpcMutualTlsConfigurationErrors({
  required Set<String> remotePeers,
  required String caFile,
  required String certificateFile,
  required String privateKeyFile,
  required Map<String, String> locomotionPrincipalCertificateFiles,
}) {
  final files = <String, String>{
    'THUNDER_GRPC_TLS_CLIENT_CA_FILE': caFile.trim(),
    'THUNDER_GRPC_TLS_CERT_FILE': certificateFile.trim(),
    'THUNDER_GRPC_TLS_KEY_FILE': privateKeyFile.trim(),
  };
  final configured = files.values.where((value) => value.isNotEmpty).length;
  final errors = <String>[];
  if (configured != 0 && configured != files.length) {
    errors.add('Brainstem gRPC mTLS requires all three TLS file settings');
  }
  if (remotePeers.isNotEmpty && configured != files.length) {
    errors.add(
      '$_grpcAllowedIpsSettings requires complete Brainstem gRPC mTLS',
    );
  }
  if (remotePeers.isNotEmpty && locomotionPrincipalCertificateFiles.isEmpty) {
    errors.add('THUNDER_LOCOMOTION_PRINCIPALS requires at least one principal');
  }
  final certificateOwners = <String, String>{};
  for (final entry in locomotionPrincipalCertificateFiles.entries) {
    if (!_isReadableFile(entry.value)) {
      errors.add(
        '${entry.key} certificate is not a readable file: ${entry.value}',
      );
    } else {
      try {
        final certificateKey = base64Encode(readPemCertificateDer(entry.value));
        final existing = certificateOwners[certificateKey];
        if (existing != null) {
          errors.add(
            'principals $existing and ${entry.key} use the same certificate',
          );
        } else {
          certificateOwners[certificateKey] = entry.key;
        }
      } on FormatException catch (error) {
        errors.add('${entry.key} certificate: ${error.message}');
      }
    }
  }
  if (configured == files.length) {
    for (final entry in files.entries) {
      if (!_isReadableFile(entry.value)) {
        errors.add('${entry.key}="${entry.value}" is not a readable file');
      }
    }
  }
  return errors;
}

Uint8List readPemCertificateDer(String path) {
  final pem = File(path).readAsStringSync().replaceAll('\r\n', '\n').trim();
  const begin = '-----BEGIN CERTIFICATE-----';
  const end = '-----END CERTIFICATE-----';
  final beginIndex = pem.indexOf(begin);
  final endIndex = pem.indexOf(end);
  if (beginIndex != 0 || endIndex <= begin.length) {
    throw const FormatException('expected one PEM CERTIFICATE block');
  }
  if (pem.indexOf(begin, begin.length) != -1 ||
      pem.indexOf(end, endIndex + end.length) != -1 ||
      pem.substring(endIndex + end.length).trim().isNotEmpty) {
    throw const FormatException('expected exactly one PEM CERTIFICATE block');
  }
  final encoded = pem
      .substring(begin.length, endIndex)
      .replaceAll(RegExp(r'\s'), '');
  if (encoded.isEmpty) {
    throw const FormatException('certificate payload is empty');
  }
  try {
    return base64Decode(encoded);
  } on FormatException {
    throw const FormatException('certificate payload is not valid base64');
  }
}

bool _isReadableFile(String path) {
  try {
    final handle = File(path).openSync(mode: FileMode.read);
    handle.closeSync();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// 解析策略目录。
///
/// 优先级：
/// 1. [primaryEnvVar]
/// 2. [legacyEnvVars]
/// 3. 默认候选目录（先 `profiles/`，再 `thunder/profiles/`）
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
  final secretFile = env['THUNDER_ARM_TELEOP_SECRET_FILE']?.trim();
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
  return env['THUNDER_ARM_TELEOP_SECRET']?.trim() ?? '';
}

/// 从环境变量读取配置，每个都有合理的默认值。
class ThunderConfig {
  final Map<String, String> _armTeleopEnvironment;
  final String Function(String path)? _armTeleopFileReader;
  bool _armTeleopSecretResolved = false;
  String? _resolvedArmTeleopSecret;
  Object? _armTeleopSecretError;
  StackTrace? _armTeleopSecretStackTrace;

  ThunderConfig({
    Map<String, String>? environment,
    String Function(String path)? readTextFile,
  }) : _armTeleopEnvironment = environment ?? Platform.environment,
       _armTeleopFileReader = readTextFile;

  int get grpcPort =>
      int.tryParse(Platform.environment['THUNDER_PORT'] ?? '') ?? 13145;
  String get imuPort =>
      Platform.environment['THUNDER_IMU_PORT'] ?? '/dev/ttyUSB1';
  String get yunzhuoPort =>
      Platform.environment['THUNDER_YUNZHUO_PORT'] ?? '/dev/yunzhuo';
  String get xboxDevice =>
      Platform.environment['THUNDER_XBOX_DEVICE'] ?? '/dev/input/js0';
  String get nc500HidrawDevice =>
      Platform.environment['THUNDER_NC500_HIDRAW_DEVICE'] ?? '/dev/hidraw0';
  String get xboxConfigPath =>
      Platform.environment['THUNDER_XBOX_CONFIG'] ?? 'thunder/config/xbox.json';

  /// 机械臂 UDP 桥接默认关闭；必须显式启用并提供受限权限的密钥文件。
  bool get armTeleopEnabled =>
      _armTeleopEnvironment['THUNDER_ARM_TELEOP_ENABLED'] == 'true';
  String get armTeleopHost =>
      _armTeleopEnvironment['THUNDER_ARM_TELEOP_HOST'] ?? '192.168.66.65';
  int get armTeleopControlPort =>
      int.tryParse(
        _armTeleopEnvironment['THUNDER_ARM_TELEOP_CONTROL_PORT'] ?? '',
      ) ??
      14600;
  int get armTeleopAckPort =>
      int.tryParse(
        _armTeleopEnvironment['THUNDER_ARM_TELEOP_ACK_PORT'] ?? '',
      ) ??
      14601;
  bool get armTeleopSixAxisOnly =>
      _armTeleopEnvironment['THUNDER_ARM_TELEOP_SIX_AXIS_ONLY']?.trim() ==
          'true' &&
      _armTeleopEnvironment['THUNDER_ARM_TELEOP_ACKNOWLEDGE_GRIPPER_DISABLED']
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
  String? get defaultProfile => Platform.environment['THUNDER_DEFAULT_PROFILE'];
  String get operatorModesPath =>
      _armTeleopEnvironment['THUNDER_OPERATOR_MODES'] ??
      'thunder/config/operator_modes.json';
  int get arbiterTimeoutSec =>
      int.tryParse(Platform.environment['THUNDER_ARBITER_TIMEOUT'] ?? '') ?? 3;
  int get grpcLeaseTimeoutMs =>
      int.tryParse(
        _armTeleopEnvironment['THUNDER_GRPC_LEASE_TIMEOUT_MS'] ?? '',
      ) ??
      300;
  Set<String> get grpcAllowedIps =>
      resolveGrpcAllowedIps(_armTeleopEnvironment);

  String get grpcTransport =>
      _armTeleopEnvironment['THUNDER_GRPC_TRANSPORT']?.trim() ?? 'mtls';
  bool get grpcDevelopmentPlaintext => grpcTransport == 'lan-dev';
  String get grpcLanAddress =>
      _armTeleopEnvironment['THUNDER_GRPC_LAN_ADDRESS']?.trim() ?? '';

  /// Compatibility alias for callers using the former client-specific name.
  Set<String> get lingtuAllowedIps => grpcAllowedIps;
  String get grpcTlsClientCaFile =>
      _armTeleopEnvironment['THUNDER_GRPC_TLS_CLIENT_CA_FILE']?.trim() ?? '';
  String get grpcTlsCertificateFile =>
      _armTeleopEnvironment['THUNDER_GRPC_TLS_CERT_FILE']?.trim() ?? '';
  String get grpcTlsPrivateKeyFile =>
      _armTeleopEnvironment['THUNDER_GRPC_TLS_KEY_FILE']?.trim() ?? '';
  Map<String, String> get locomotionPrincipalCertificateFiles =>
      parseLocomotionPrincipalCertificateFiles(
        _armTeleopEnvironment['THUNDER_LOCOMOTION_PRINCIPALS'],
      );
  Map<String, Uint8List> get locomotionPrincipals => grpcDevelopmentPlaintext
      ? const <String, Uint8List>{}
      : Map.unmodifiable({
          for (final entry in locomotionPrincipalCertificateFiles.entries)
            entry.key: readPemCertificateDer(entry.value),
        });
  bool get grpcMutualTlsEnabled =>
      !grpcDevelopmentPlaintext &&
      grpcTlsClientCaFile.isNotEmpty &&
      grpcTlsCertificateFile.isNotEmpty &&
      grpcTlsPrivateKeyFile.isNotEmpty;
  int get sensorLowThreshold =>
      int.tryParse(
        Platform.environment['THUNDER_SENSOR_LOW_THRESHOLD'] ?? '',
      ) ??
      3;
  int get shutdownTimeoutSec =>
      int.tryParse(Platform.environment['THUNDER_SHUTDOWN_TIMEOUT'] ?? '') ?? 8;
  int get startupTimeoutSec =>
      int.tryParse(Platform.environment['THUNDER_STARTUP_TIMEOUT'] ?? '') ?? 10;

  /// 关节位置安全限位（绝对值，rad）。任一关节超过此值立即触发 Fault。
  /// 默认 3.14 rad（π，物理不可能超过），设置更小值可提供提前保护。
  double get jointLimitRad =>
      double.tryParse(Platform.environment['THUNDER_JOINT_LIMIT_RAD'] ?? '') ??
      3.14;
  String get profileDir => resolveProfileDir(
    primaryEnvVar: 'THUNDER_PROFILE_DIR',
    legacyEnvVars: const ['THUNDER_PROFILES_DIR'],
  );

  /// 日志目录（默认 'logs'，空字符串禁用文件日志）。
  String get logDir => Platform.environment['THUNDER_LOG_DIR'] ?? 'logs';
  bool get debugTui => Platform.environment['THUNDER_DEBUG_TUI'] == 'true';

  Duration get arbiterTimeout => Duration(seconds: arbiterTimeoutSec);
  Duration get grpcLeaseTimeout => Duration(milliseconds: grpcLeaseTimeoutMs);
  Duration get shutdownTimeout => Duration(seconds: shutdownTimeoutSec);
  Duration get startupTimeout => Duration(seconds: startupTimeoutSec);

  /// 校验配置有效性，返回所有错误描述列表。空列表表示配置合法。
  List<String> validate() {
    final errors = <String>[];
    if (grpcPort < 1 || grpcPort > 65535) {
      errors.add('THUNDER_PORT=$grpcPort 超出范围 [1-65535]');
    }
    if (arbiterTimeoutSec < 0 || arbiterTimeoutSec > 3600) {
      errors.add(
        'THUNDER_ARBITER_TIMEOUT=${arbiterTimeoutSec}s 需在 [0, 3600] 范围内（0=永不释放）',
      );
    }
    if (grpcLeaseTimeoutMs < 100 || grpcLeaseTimeoutMs > 10000) {
      errors.add(
        'THUNDER_GRPC_LEASE_TIMEOUT_MS=$grpcLeaseTimeoutMs '
        'must be within [100, 10000]',
      );
    }
    if (!motionTimeoutsSafe(
      arbiterTimeout: arbiterTimeout,
      grpcLeaseTimeout: grpcLeaseTimeout,
    )) {
      errors.add(
        'THUNDER_GRPC_LEASE_TIMEOUT_MS=${grpcLeaseTimeoutMs}ms must be '
        'strictly shorter than THUNDER_ARBITER_TIMEOUT=${arbiterTimeoutSec}s '
        '(or set arbiter timeout to 0)',
      );
    }
    var allowedPeers = const <String>{};
    try {
      allowedPeers = grpcAllowedIps;
      if (allowedPeers.length > 16) {
        errors.add('$_grpcAllowedIpsSettings supports at most 16 peers');
      }
    } on FormatException catch (error) {
      errors.add('$_grpcAllowedIpsSettings: ${error.message}');
    }
    errors.addAll(
      grpcLanDevelopmentConfigurationErrors(
        transport: grpcTransport,
        address: grpcLanAddress,
        peers: allowedPeers,
      ),
    );
    if (!grpcDevelopmentPlaintext) {
      var principalCertificates = const <String, String>{};
      try {
        principalCertificates = locomotionPrincipalCertificateFiles;
        if (principalCertificates.length > 16) {
          errors.add(
            'THUNDER_LOCOMOTION_PRINCIPALS supports at most 16 principals',
          );
        }
      } on FormatException catch (error) {
        errors.add('THUNDER_LOCOMOTION_PRINCIPALS: ${error.message}');
      }
      errors.addAll(
        grpcMutualTlsConfigurationErrors(
          remotePeers: allowedPeers,
          caFile: grpcTlsClientCaFile,
          certificateFile: grpcTlsCertificateFile,
          privateKeyFile: grpcTlsPrivateKeyFile,
          locomotionPrincipalCertificateFiles: principalCertificates,
        ),
      );
    }
    if (shutdownTimeoutSec < 1 || shutdownTimeoutSec > 300) {
      errors.add(
        'THUNDER_SHUTDOWN_TIMEOUT=${shutdownTimeoutSec}s 需在 [1, 300] 范围内',
      );
    }
    if (startupTimeoutSec < 1 || startupTimeoutSec > 300) {
      errors.add(
        'THUNDER_STARTUP_TIMEOUT=${startupTimeoutSec}s 需在 [1, 300] 范围内',
      );
    }
    if (jointLimitRad <= 0 || !jointLimitRad.isFinite) {
      errors.add('THUNDER_JOINT_LIMIT_RAD=$jointLimitRad 必须为有限正数');
    }
    if (sensorLowThreshold < 1) {
      errors.add('THUNDER_SENSOR_LOW_THRESHOLD=$sensorLowThreshold 至少需 1');
    }
    if (!_directoryExists(profileDir)) {
      errors.add('THUNDER_PROFILE_DIR="$profileDir" 目录不存在');
    }
    _validateArmTeleopProfileSwitches(errors);
    return errors;
  }

  void _validateArmTeleopProfileSwitches(List<String> errors) {
    const sixAxisKey = 'THUNDER_ARM_TELEOP_SIX_AXIS_ONLY';
    const acknowledgeKey = 'THUNDER_ARM_TELEOP_ACKNOWLEDGE_GRIPPER_DISABLED';
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
      'grpcLeaseTimeout=${grpcLeaseTimeoutMs}ms '
      'grpcAllowedIps=${grpcAllowedIps.join(",")} '
      'grpcTransport=$grpcTransport '
      'grpcMutualTls=${grpcMutualTlsEnabled ? "enabled" : "disabled"} '
      'sensorLowThreshold=$sensorLowThreshold '
      'shutdownTimeout=${shutdownTimeoutSec}s '
      'startupTimeout=${startupTimeoutSec}s '
      'jointLimitRad=$jointLimitRad '
      'logDir=$logDir debugTui=$debugTui';
}

/// 初始化 Logger，级别由 THUNDER_LOG 环境变量控制（默认 INFO）。
///
/// [logDir] 非空时，同时写入每日轮转日志文件（thunder_YYYYMMDD.log）。
/// 启动时自动删除 7 天前的旧日志文件。
void setupLogging({String logDir = ''}) {
  final levelName = Platform.environment['THUNDER_LOG'] ?? 'INFO';
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
        '$logDir${Platform.pathSeparator}thunder_$dateStr.log',
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

/// 删除 [dir] 中超过 7 天的 thunder_*.log 文件。
void _cleanOldLogs(Directory dir) {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  try {
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('thunder_') || !name.endsWith('.log')) continue;
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
