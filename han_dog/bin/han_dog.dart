import 'dart:async';
import 'dart:io';

import 'package:frequency_watch/frequency_watch.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_message/han_dog_message.dart' as msg;
import 'package:logging/logging.dart';
import 'package:cms/cms.dart';
import 'package:han_dog/src/app/config.dart';
import 'package:han_dog/src/app/monitoring.dart';

final _log = Logger('han_dog');
final _cfg = HanDogConfig();

/// 所有需要在关机时取消的 subscription
final _subs = <StreamSubscription<Object?>>[];

/// 用于异常退出时关闭 gRPC、释放端口
grpc.Server? _grpcServerForCleanup;

/// 策略热加载定时器（关机时取消）
Timer? _profileReloadTimer;

void main() {
  setupLogging(logDir: _cfg.logDir);
  runZonedGuarded(
    () async => _run(),
    (error, stack) {
      _log.severe('Uncaught: $error\n$stack');
      (() async {
        try {
          await _grpcServerForCleanup?.shutdown();
          _log.info('gRPC port ${_cfg.grpcPort} released.');
        } catch (_) {}
        exit(1);
      })();
    },
  );
}

Future<void> _run() async {
  Bloc.observer = SimpleBlocObserver(_log);

  // ──── 0. 配置校验（前置检查）─────────────────────────────────
  final configErrors = _cfg.validate();
  if (configErrors.isNotEmpty) {
    for (final err in configErrors) {
      _log.severe('Config error: $err');
    }
    exit(1);
  }

  RealFrequency.manager.watch();
  _log.info('han_dog starting — $_cfg');

  // ──── 0b. 策略加载（必须先于一切设备初始化）───────────────────
  // RobotProfile 是所有机器人参数的唯一真相来源：
  // standingPose / sittingPose / kp / kd / modelPath 均来自此处。
  final profiles = await loadProfiles(_cfg.profileDir);
  if (profiles.isEmpty) {
    _log.severe(
        'No profiles found in "${_cfg.profileDir}" — '
        'cannot start without at least one profile. '
        'Create a JSON profile file and set HAN_DOG_PROFILE_DIR if needed.');
    exit(1);
  }

  final defaultName = _cfg.defaultProfile;
  final RobotProfile defaultProfile;
  if (defaultName != null && profiles.containsKey(defaultName)) {
    defaultProfile = profiles[defaultName]!;
  } else {
    if (defaultName != null) {
      _log.warning(
          'HAN_DOG_DEFAULT_PROFILE="$defaultName" not found in profiles '
          '(available: ${profiles.keys.join(", ")}). '
          'Using first profile: "${profiles.keys.first}".');
    }
    defaultProfile = profiles.values.first;
  }
  _log.info('Default profile: ${defaultProfile.name} (model=${defaultProfile.modelPath})');

  final clock = StreamController<void>.broadcast();

  // ──── 1. 设备初始化 ────────────────────────────────────────
  final imu = RealImu(_cfg.imuPort);
  if (!imu.open()) {
    _log.severe('IMU open failed on ${_cfg.imuPort}');
    return;
  }
  _log.info('IMU opened.');

  // PCAN USB 通道映射（由硬件接线决定）
  final joint = RealJoint(
    fr: .usbbus2,
    fl: .usbbus4,
    rr: .usbbus1,
    rl: .usbbus3,
  );
  if (!joint.open()) {
    _log.severe('Joint PCAN open failed');
    imu.dispose();
    return;
  }
  _log.info('Joint PCAN opened.');

  // 发送 setReporting x3（带间隔），防止刚 open 后首帧丢失
  for (var retry = 0; retry < 3; retry++) {
    joint.setReporting(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await _checkJointReporting(joint);

  // ──── 2. Brain（参数来自默认策略）─────────────────────────────
  final brain = Brain(
    imu: imu,
    joint: joint,
    clock: clock,
    standingPose: defaultProfile.standingPose,
    sittingPose: defaultProfile.sittingPose,
  );
  const modelLoadMaxAttempts = 3;
  bool modelLoaded = false;
  for (var attempt = 1; attempt <= modelLoadMaxAttempts; attempt++) {
    try {
      await brain.loadModel(defaultProfile.modelPath);
      _log.info('ONNX model loaded (attempt $attempt).');
      modelLoaded = true;
      break;
    } catch (e) {
      if (attempt == modelLoadMaxAttempts) {
        _log.severe('Failed to load ONNX model after $modelLoadMaxAttempts attempts: $e');
      } else {
        final delay = Duration(seconds: attempt * 2);
        _log.warning('ONNX model load failed (attempt $attempt/$modelLoadMaxAttempts): $e — retrying in $delay');
        await Future<void>.delayed(delay);
      }
    }
  }
  if (!modelLoaded) {
    joint.disable();
    imu.dispose();
    joint.dispose();
    return;
  }

  joint.kpExt = defaultProfile.inferKp;
  joint.kdExt = defaultProfile.inferKd;

  // ──── 3. YUNZHUO 遥控器 ────────────────────────────────────
  final controller = RealController(_cfg.yunzhuoPort);
  if (!controller.open()) {
    _log.severe('Failed to open YUNZHUO controller on ${_cfg.yunzhuoPort}');
    imu.dispose();
    joint.dispose();
    return;
  }
  _log.info('YUNZHUO controller opened.');

  // ──── 4. FSM + 仲裁器 ──────────────────────────────────────
  final M m = M(brain)..add(Init());
  _subs.add(m.stream.listen((s) => _log.info('CMS state: $s')));
  try {
    await m.stream
        .firstWhere((s) => s is Grounded)
        .timeout(_cfg.startupTimeout);
  } on TimeoutException {
    _log.severe(
        'FSM 未能在 ${_cfg.startupTimeoutSec}s 内到达 Grounded 状态 — 中止启动');
    await m.close();
    joint.disable();
    imu.dispose();
    joint.dispose();
    controller.dispose();
    return;
  }
  _log.info('CMS initialized: ${m.state}');

  final arbiter = ControlArbiter(m, timeout: _cfg.arbiterTimeout);
  _subs.add(arbiter.ownerStream.listen((owner) {
    _log.info('Arbiter control owner: ${owner ?? "none"}');
  }));
  // IMU 串口断联 → 立即触发 FSM Fault，防止机器人用陈旧读数盲推理。
  imu.onDisconnect = (reason) => arbiter.fault(reason);

  // 推理输出 → 电机动作
  _subs.add(brain.nextActionStream.listen(
    (action) {
      // TODO(phase3): Enable motor output after data stream validation.
      // joint.sendAction(action);
    },
    onError: (Object error, StackTrace st) {
      _log.severe('Inference stream error: $error', error, st);
      arbiter.fault('Inference stream error: $error');
    },
    onDone: () {
      _log.severe('Inference stream closed unexpectedly');
      arbiter.fault('Inference stream closed');
    },
  ));

  // YUNZHUO 遥控器 → CMS 命令映射（增益来自默认策略）
  final controlDog = RealControlDog(
    brain: brain,
    imu: imu,
    joint: joint,
    arbiter: arbiter,
    inferKd: defaultProfile.inferKd,
    inferKp: defaultProfile.inferKp,
    standUpKd: defaultProfile.standUpKd,
    standUpKp: defaultProfile.standUpKp,
    sitDownKd: defaultProfile.sitDownKd,
    sitDownKp: defaultProfile.sitDownKp,
    controller: controller,
  );

  // ──── 4b. 策略管理（始终创建，ProfileManager 为必需组件）────────
  final profileManager = ProfileManager(
    profiles: profiles,
    brain: brain,
    controlDog: controlDog,
    initial: defaultProfile.name,
  );
  controlDog.onProfileSwitch = () => profileManager.toggle();
  _log.info('ProfileManager ready: ${profiles.keys.join(", ")}');

  // ──── 4c. 策略热加载（每 30s 扫描 profileDir）────────────────
  _profileReloadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    profileManager.reload(_cfg.profileDir).catchError((Object e, StackTrace st) {
      _log.warning('Profile hot-reload failed', e, st);
    });
  });

  // ──── 5. 监控 ──────────────────────────────────────────────
  _subs.add(startSensorMonitoring(
    imu: imu,
    joint: joint,
    arbiter: arbiter,
    threshold: _cfg.sensorLowThreshold,
  ));
  _subs.add(startControllerMonitoring(
    controller: controller,
    arbiter: arbiter,
  ));
  _subs.add(startJointLimitMonitoring(
    joint: joint,
    arbiter: arbiter,
    limitRad: _cfg.jointLimitRad,
  ));

  // ──── 6. gRPC 服务器 ───────────────────────────────────────
  final imuBroadcast = imu.stateStream.asBroadcastStream();
  final jointBroadcast = joint.reportStream.asBroadcastStream();
  final serverStartTime = DateTime.now();

  msg.Duration elapsed() =>
      msg.Duration.fromDart(DateTime.now().difference(serverStartTime));

  final cmsService = UnifiedCmsServer(
    brain: brain,
    m: m,
    mode: CmsMode.hardware,
    arbiter: arbiter,
    motor: joint,
    robotType: msg.RobotType.MINI,
    imuStreamFactory: () => imuBroadcast.expand((s) => s).map(
          (s) => msg.Imu(
            gyroscope: msg.Vector3(
                x: s.gyroscope.x, y: s.gyroscope.y, z: s.gyroscope.z),
            quaternion: msg.Quaternion(
                w: s.quaternion.w,
                x: s.quaternion.x,
                y: s.quaternion.y,
                z: s.quaternion.z),
            timestamp: elapsed(),
          ),
        ),
    jointStreamFactory: () => jointBroadcast.map(
          (r) => msg.Joint(
            singleJoint: msg.SingleJoint(
              id: r.$1,
              position: r.$2.position,
              velocity: r.$2.velocity,
              torque: r.$2.torque,
              status: r.$2.status.value,
            ),
            timestamp: elapsed(),
          ),
        ),
  );
  cmsService.profileManager = profileManager;
  final grpcServer = await _startGrpc(cmsService);
  _grpcServerForCleanup = grpcServer;

  // ──── 7. 信号处理 + 时钟 ───────────────────────────────────
  Timer? clockTimer;
  _registerShutdown(
    m: m,
    joint: joint,
    arbiter: arbiter,
    grpcServer: grpcServer,
    controlDog: controlDog,
    controller: controller,
    imu: imu,
    brain: brain,
    getClockTimer: () => clockTimer,
  );

  _log.info('gRPC + YUNZHUO 就绪. 电机输出已禁用(仅数据流验证).');

  clockTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    clock.add(null);
  });

  if (_cfg.debugTui) {
    startDebugTui(imu: imu, joint: joint, m: m, arbiter: arbiter);
  }
}

// ─── 辅助函数 ──────────────────────────────────────────────────

/// 检查 16 个关节的主动上报状态。
Future<void> _checkJointReporting(RealJoint joint) async {
  const names = [
    'FR Hip', 'FR Thigh', 'FR Calf', 'FR Foot',
    'FL Hip', 'FL Thigh', 'FL Calf', 'FL Foot',
    'RR Hip', 'RR Thigh', 'RR Calf', 'RR Foot',
    'RL Hip', 'RL Thigh', 'RL Calf', 'RL Foot',
  ];
  await Future<void>.delayed(const Duration(seconds: 1));
  final noReport = <String>[];
  final hasReport = <String>[];
  for (var i = 0; i < joint.frequencyWatches.length; i++) {
    if (joint.frequencyWatches[i].value > 0) {
      hasReport.add(names[i]);
    } else {
      noReport.add(names[i]);
    }
  }
  if (noReport.isEmpty) {
    _log.info('主动上报: 16/16 关节已收到');
  } else {
    _log.info('主动上报 已收到: ${hasReport.join(", ")}');
    _log.warning(
        '主动上报 未收到: ${noReport.join(", ")} (请检查 CAN/电机或重新上电)');
  }
}

/// 启动 gRPC 服务器，处理端口冲突。
Future<grpc.Server> _startGrpc(UnifiedCmsServer cmsService) async {
  grpc.Server create() => grpc.Server.create(
    services: [cmsService],
    errorHandler: (error, trace) => _log.severe('gRPC server error: $error'),
  );

  var server = create();
  try {
    await server.serve(address: InternetAddress.anyIPv4, port: _cfg.grpcPort);
  } on SocketException catch (e) {
    if (e.osError?.errorCode == 98) {
      _log.warning(
          'Port ${_cfg.grpcPort} in use, freeing (fuser -k ${_cfg.grpcPort}/tcp)...');
      await Process.run('fuser', ['-k', '${_cfg.grpcPort}/tcp'],
          runInShell: false);
      await Future<void>.delayed(const Duration(seconds: 1));
      server = create();
      await server.serve(
          address: InternetAddress.anyIPv4, port: _cfg.grpcPort);
    } else {
      rethrow;
    }
  }
  _log.info(
      'gRPC server listening on 0.0.0.0:${_cfg.grpcPort} (accessible from network)');
  return server;
}

/// 注册 SIGINT/SIGTERM 处理：安全坐下 → 禁用电机 → 释放资源。
void _registerShutdown({
  required M m,
  required RealJoint joint,
  required ControlArbiter arbiter,
  required grpc.Server grpcServer,
  required RealControlDog controlDog,
  required RealController controller,
  required RealImu imu,
  required Brain brain,
  required Timer? Function() getClockTimer,
}) {
  var shuttingDown = false;

  Future<void> handle(ProcessSignal signal) async {
    if (shuttingDown) return;
    shuttingDown = true;
    _log.info('Received $signal — starting graceful shutdown');

    // 全局关机总超时：防止任意步骤挂起导致进程永久卡死
    const hardDeadline = Duration(seconds: 15);
    Timer(hardDeadline, () {
      _log.severe('Shutdown exceeded ${hardDeadline.inSeconds}s hard deadline — forcing exit(1)');
      exit(1);
    });

    try {
      final current = m.state;
      if (current is Walking || current is Transitioning) {
        arbiter.fault('Process signal $signal');
        _log.info('Waiting for safe posture...');
        await m.stream
            .firstWhere((s) => s is Standing || s is Grounded)
            .timeout(_cfg.shutdownTimeout);
        _log.info('Reached safe posture: ${m.state}');
      }

      if (m.state is Standing) {
        m.add(const A.sitDown());
        _log.info('Sitting down...');
        await m.stream
            .firstWhere((s) => s is Grounded)
            .timeout(_cfg.shutdownTimeout);
        _log.info('Grounded.');
      }
    } on TimeoutException {
      _log.warning('FSM shutdown timeout, proceeding with disable.');
    } catch (e) {
      _log.warning('Shutdown FSM error: $e, proceeding with disable.');
    }

    joint.disable();
    _log.info('Motors disabled safely.');

    try {
      await grpcServer.shutdown().timeout(const Duration(seconds: 3));
      _log.info('gRPC server stopped.');
    } on TimeoutException {
      _log.warning('gRPC shutdown timed out — continuing.');
    }

    // 释放所有资源
    for (final sub in _subs) {
      try { sub.cancel(); } catch (_) {}
    }
    _subs.clear();
    getClockTimer()?.cancel();
    _profileReloadTimer?.cancel();
    for (final disposable in [arbiter, controlDog, controller, imu, joint, brain]) {
      try { (disposable as dynamic).dispose(); } catch (_) {}
    }
    try { await m.close().timeout(const Duration(seconds: 2)); } catch (_) {}
    _log.info('All resources released — exit(0)');
    exit(0);
  }

  _subs.add(ProcessSignal.sigint.watch().listen((s) => handle(s)));
  if (!Platform.isWindows) {
    _subs.add(ProcessSignal.sigterm.watch().listen((s) => handle(s)));
  }
}
