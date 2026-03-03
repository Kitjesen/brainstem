import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';

final _log = Logger('han_dog.medulla');

// ─── 配置（从环境变量读取，有默认值）─────────────────────────
int get _port => int.tryParse(Platform.environment['MEDULLA_PORT'] ?? '') ?? 13145;
String get _profileDir => Platform.environment['MEDULLA_PROFILE_DIR'] ?? 'profiles';
String? get _defaultProfile => Platform.environment['MEDULLA_DEFAULT_PROFILE'];
int get _historySize => int.tryParse(Platform.environment['MEDULLA_HISTORY_SIZE'] ?? '') ?? 1;

Future<void> main() async {
  _setupLogging();

  // ── 策略加载（必须先于 Brain 初始化）─────────────────────────
  // RobotProfile 是所有机器人参数的唯一真相来源：
  // standingPose / sittingPose / kp / kd / modelPath 均来自此处。
  final profiles = await loadProfiles(_profileDir);
  if (profiles.isEmpty) {
    _log.severe(
        'No profiles found in "$_profileDir" — '
        'cannot start without at least one profile. '
        'Create a JSON profile file and set MEDULLA_PROFILE_DIR if needed.');
    exit(1);
  }

  final String defaultName;
  final RobotProfile defaultProfile;
  final requested = _defaultProfile;
  if (requested != null && profiles.containsKey(requested)) {
    defaultName = requested;
    defaultProfile = profiles[requested]!;
  } else {
    if (requested != null) {
      _log.warning(
          'MEDULLA_DEFAULT_PROFILE="$requested" not found in profiles '
          '(available: ${profiles.keys.join(", ")}). '
          'Using first profile: "${profiles.keys.first}".');
    }
    defaultName = profiles.keys.first;
    defaultProfile = profiles.values.first;
  }
  _log.info('medulla starting — port=$_port profile=$defaultName (model=${defaultProfile.modelPath})');

  // ── 传感器 ────────────────────────────────────────────────
  //
  // 仿真模式：SimSensorService（MuJoCo 通过 Step RPC 注入）
  //
  // 真实硬件：替换为 CAN 总线实现，例如：
  //   final imu   = CanImuService(canInterface: 'can0');
  //   final joint = CanJointService(canInterface: 'can0');
  //   final motor = CanMotorService(canInterface: 'can0');
  final sim = SimSensorService(standingPose: defaultProfile.standingPose);

  // ── 时钟 ──────────────────────────────────────────────────
  //
  // 仿真模式：MuJoCo 通过 Tick RPC 驱动，不需要 Timer。
  //
  // 真实硬件模式：取消注释下面的 Timer，以 50Hz 驱动控制循环：
  //   Timer? hwClock;
  //   hwClock = Timer.periodic(
  //     const Duration(milliseconds: 20),
  //     (_) => clock.add(null),
  //   );
  //   // 关机时: hwClock?.cancel();
  final clock = StreamController<void>.broadcast();

  // ── 推理核心（参数来自默认策略）──────────────────────────────
  final brain = Brain(
    imu: sim,
    joint: sim,
    clock: clock,
    standingPose: defaultProfile.standingPose,
    sittingPose: defaultProfile.sittingPose,
    historySize: _historySize,
    standUpCounts: defaultProfile.standUpCounts,
    sitDownCounts: defaultProfile.sitDownCounts,
  );

  try {
    await brain.loadModel(defaultProfile.modelPath);
    _log.info('ONNX model loaded from ${defaultProfile.modelPath}');
  } catch (e) {
    _log.severe('Failed to load model: $e');
    exit(1);
  }

  // ── FSM ───────────────────────────────────────────────────
  final m = M(brain);

  // ── 策略管理（始终创建）──────────────────────────────────────
  final profileManager = ProfileManager(
    profiles: profiles,
    brain: brain,
    initial: defaultName,
  );
  _log.info('ProfileManager ready: ${profiles.keys.join(", ")}');

  // ── gRPC 服务器 ────────────────────────────────────────────
  final cmsService = UnifiedCmsServer(
    brain: brain,
    m: m,
    mode: CmsMode.simulation,
    simInjector: sim,
  )..profileManager = profileManager;
  final server = Server.create(
    services: [cmsService],
  );

  await server.serve(port: _port);
  _log.info('CMS gRPC server listening on :$_port');

  // ── 优雅关机 ───────────────────────────────────────────────
  ProcessSignal.sigint.watch().listen((_) => _shutdown(m, brain, clock, server));
  ProcessSignal.sigterm.watch().listen((_) => _shutdown(m, brain, clock, server));
}

Future<void> _shutdown(
  M m,
  Brain brain,
  StreamController<void> clock,
  Server server,
) async {
  _log.info('Shutdown signal received — starting graceful shutdown');

  // 1. 发坐下指令
  m.add(const A.sitDown());

  // 2. 等 FSM 真正到 Grounded（最多 10 秒）
  try {
    await m.stream
        .firstWhere((s) => s is Grounded)
        .timeout(const Duration(seconds: 10));
    _log.info('FSM reached Grounded — safe to power off');
  } on TimeoutException {
    _log.warning('Shutdown timeout: FSM did not reach Grounded in 10s');
  }

  // 3. 释放资源
  await m.close();
  brain.dispose();
  await clock.close();
  await server.shutdown();
  _log.info('Shutdown complete');
  exit(0);
}

void _setupLogging() {
  // 从环境变量控制日志级别：MEDULLA_LOG=FINE / INFO / WARNING / SEVERE
  final levelName = Platform.environment['MEDULLA_LOG'] ?? 'INFO';
  final level = Level.LEVELS.firstWhere(
    (l) => l.name == levelName.toUpperCase(),
    orElse: () => Level.INFO,
  );
  Logger.root.level = level;
  Logger.root.onRecord.listen((r) {
    final prefix = '${r.time.toIso8601String()} ${r.level.name.padRight(7)} ${r.loggerName}';
    if (r.level >= Level.WARNING) {
      stderr.writeln('$prefix: ${r.message}');
      if (r.error != null) stderr.writeln('  error: ${r.error}');
      if (r.stackTrace != null) stderr.writeln('  ${r.stackTrace}');
    } else {
      stdout.writeln('$prefix: ${r.message}');
    }
  });
}
