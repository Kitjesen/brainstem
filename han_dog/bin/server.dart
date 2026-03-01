import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

final _log = Logger('medulla');

// ─── 配置（从环境变量读取，有默认值）─────────────────────────
int get _port => int.tryParse(Platform.environment['MEDULLA_PORT'] ?? '') ?? 13145;
String get _modelPath => Platform.environment['MEDULLA_MODEL'] ?? 'model/policy.onnx';
String get _profileDir => Platform.environment['MEDULLA_PROFILE_DIR'] ?? 'profiles';
int get _historySize => int.tryParse(Platform.environment['MEDULLA_HISTORY_SIZE'] ?? '') ?? 1;
int get _standUpCounts => int.tryParse(Platform.environment['MEDULLA_STANDUP_COUNTS'] ?? '') ?? 150;
int get _sitDownCounts => int.tryParse(Platform.environment['MEDULLA_SITDOWN_COUNTS'] ?? '') ?? 150;

// ─── 站立姿态（rad）─────────────────────────────────────────
// dart format off
final _standingPose = JointsMatrix(
  0, -0.64,  1.6,   // FR: hip, thigh, calf
  0,  0.64, -1.6,   // FL
  0,  0.64, -1.6,   // RR
  0, -0.64,  1.6,   // RL
  0,  0,    0,  0,  // foot × 4
);
// dart format on

Future<void> main() async {
  _setupLogging();

  _log.info('medulla starting — port=$_port model=$_modelPath');

  // ── 传感器 ────────────────────────────────────────────────
  //
  // 仿真模式：SimSensorService（MuJoCo 通过 Step RPC 注入）
  //
  // 真实硬件：替换为 CAN 总线实现，例如：
  //   final imu   = CanImuService(canInterface: 'can0');
  //   final joint = CanJointService(canInterface: 'can0');
  //   final motor = CanMotorService(canInterface: 'can0');
  final sim = SimSensorService(standingPose: _standingPose);

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

  // ── 推理核心 ───────────────────────────────────────────────
  final brain = Brain(
    imu: sim,
    joint: sim,
    clock: clock,
    standingPose: _standingPose,
    sittingPose: JointsMatrix.zero(),
    historySize: _historySize,
    standUpCounts: _standUpCounts,
    sitDownCounts: _sitDownCounts,
  );

  try {
    await brain.loadModel(_modelPath);
    _log.info('ONNX model loaded from $_modelPath');
  } catch (e) {
    _log.severe('Failed to load model: $e');
    exit(1);
  }

  // ── FSM ───────────────────────────────────────────────────
  final m = M(brain);

  // ── 策略管理 ─────────────────────────────────────────────
  final profiles = await loadProfiles(_profileDir);
  ProfileManager? profileManager;
  if (profiles.isNotEmpty) {
    profileManager = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: profiles.keys.first,
    );
    _log.info('ProfileManager ready: ${profiles.keys.join(", ")}');
  }

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
