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

/// 用于异常退出时禁用电机
RealJoint? _jointForCleanup;

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
          _jointForCleanup?.disable();
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
  final historySize = await _resolveHistorySize(defaultProfile);
  final modelInputName = await _resolveInputName(defaultProfile);
  _log.info(
      'Resolved historySize=$historySize inputName=$modelInputName '
      '(model=${defaultProfile.modelPath})');

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
    fr: .usbbus1,
    fl: .usbbus2,
    rr: .usbbus3,
    rl: .usbbus4,
  );
  if (!joint.open()) {
    _log.severe('Joint PCAN open failed');
    imu.dispose();
    return;
  }
  _log.info('Joint PCAN opened.');

  // 清除上次异常退出遗留的 fault
  _log.info('Clearing motor faults...');
  joint.clearFaults();
  await Future<void>.delayed(const Duration(milliseconds: 200));

  // 设置足轮 cantimeout = 500ms，程序崩溃后轮子自动停转
  _log.info('Setting foot wheel canTimeout...');
  joint.setFootWheelCantimeout(500000);
  await Future<void>.delayed(const Duration(milliseconds: 100));

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
    historySize: historySize,
    standUpCounts: defaultProfile.standUpCounts,
    sitDownCounts: defaultProfile.sitDownCounts,
  );
  const modelLoadMaxAttempts = 3;
  bool modelLoaded = false;
  for (var attempt = 1; attempt <= modelLoadMaxAttempts; attempt++) {
    try {
      await brain.loadModel(
        defaultProfile.modelPath,
        inputName: modelInputName,
      );
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

  // ──── 3. YUNZHUO 遥控器（可选，打不开则仅 gRPC 控制）─────────
  RealController? controller;
  {
    final c = RealController(_cfg.yunzhuoPort);
    if (c.open()) {
      controller = c;
      _log.info('YUNZHUO controller opened.');
    } else {
      _log.warning(
        'YUNZHUO controller not available on ${_cfg.yunzhuoPort} — '
        'running in gRPC-only mode (no joystick control)',
      );
    }
  }

  // ──── 4. FSM + 仲裁器 ──────────────────────────────────────
  final M m = M(brain)..add(Init());
  _subs.add(m.stream.listen((s) {
    _log.info('CMS state: $s');
  }));
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
    controller?.dispose();
    return;
  }
  _log.info('CMS initialized: ${m.state}');

  final arbiter = ControlArbiter(m, timeout: _cfg.arbiterTimeout);
  _subs.add(arbiter.ownerStream.listen((owner) {
    _log.info('Arbiter control owner: ${owner ?? "none"}');
  }));
  // IMU 串口断联 → 记录警告。频率监控会在持续低频时触发 Fault。
  imu.onDisconnect = (reason) {
    _log.warning('IMU disconnect: $reason');
  };

  // ──── 4a. Motor health manager ─────────────────────────────
  final motorHealth = MotorHealthManager(
    joint: joint,
    requestFault: (reason) => arbiter.fault(reason),
  );
  _subs.add(motorHealth.healthStream.listen((event) {
    switch (event.severity) {
      case MotorSeverity.transient:
        _log.fine('Motor health: $event');
      case MotorSeverity.healthy:
        _log.info('Motor health: $event');
      case MotorSeverity.degraded:
        _log.warning('Motor health: $event');
      case MotorSeverity.critical:
        _log.severe('Motor health: $event');
    }
  }));
  // CMS state → recovery: when Grounded with faulted motors, attempt per-joint
  // verified recovery instead of blind clear-all.
  _subs.add(m.stream.listen((s) {
    if (s is Grounded && motorHealth.hasFaults) {
      _log.info('Reached Grounded with faulted motors — starting recovery');
      motorHealth.recoverFaults();
    }
  }));

  var motorOutputEnabled = false;

  // 推理输出 → 电机动作 (gated through MotorHealthManager)
  var _actionCount = 0;
  _subs.add(brain.nextActionStream.listen(
    (action) {
      _actionCount++;
      if (_actionCount <= 3 || _actionCount % 50 == 0) {
        _log.info('ACTION[$_actionCount] enabled=$motorOutputEnabled '
            'state=${arbiter.state.runtimeType} '
            'a0=${action.values[0].toStringAsFixed(3)}');
      }
      if (!motorOutputEnabled) return;

      if (arbiter.state is Grounded) {
        joint.sendAction(joint.position.discardFoot());
        return;
      }

      final gated = motorHealth.gateAction(action, joint.position);
      joint.sendAction(gated);
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

  // YUNZHUO 遥控器 → CMS 命令映射（仅在遥控器可用时创建）
  RealControlDog? controlDog;
  ProfileManager? profileManager;
  if (controller != null) {
    controlDog = RealControlDog(
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

    // ──── 4b. 策略管理 ───────────────────────────────────────────
    profileManager = ProfileManager(
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: defaultProfile.name,
    );
    controlDog.onProfileSwitch = () => profileManager!.toggle();
    controlDog.onMotorEnableChanged = (enabled) {
      motorOutputEnabled = enabled;
    };
    _log.info('ProfileManager ready: ${profiles.keys.join(", ")}');
  } else {
    _log.info('No controller — motor enable via gRPC only');
  }

  // ──── 4c. 策略热加载（每 30s 扫描 profileDir）────────────────
  if (profileManager != null) {
    _profileReloadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      profileManager!.reload(_cfg.profileDir).catchError((Object e, StackTrace st) {
        _log.warning('Profile hot-reload failed', e, st);
      });
    });
  }

  // ──── 5. 监控 ──────────────────────────────────────────────
  _subs.add(startSensorMonitoring(
    imu: imu,
    joint: joint,
    arbiter: arbiter,
    threshold: _cfg.sensorLowThreshold,
  ));
  if (controller != null) {
    _subs.add(startControllerMonitoring(
      controller: controller,
      arbiter: arbiter,
    ));
  }
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
  cmsService.joint = joint;
  // 无遥控器时，gRPC Enable/Disable 直接控制 motorOutputEnabled
  if (controlDog == null) {
    cmsService.onMotorEnableChanged = (enabled) {
      motorOutputEnabled = enabled;
      _log.info('motorOutputEnabled=$enabled (via gRPC)');
    };
  }
  final grpcServer = await _startGrpc(cmsService);
  _grpcServerForCleanup = grpcServer;
  _jointForCleanup = joint;

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
    motorHealth: motorHealth,
    getClockTimer: () => clockTimer,
  );

  _log.info('gRPC + YUNZHUO 就绪. 电机输出受 CH5 使能控制；Grounded 时保持当前姿态.');

  clockTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    clock.add(null);
  });

  // ──── 8. 低压保护（每 10 秒检测一次）──────────────────────────
  const lowVoltageThreshold = 42.0;
  var lowVoltageTriggered = false;
  Timer.periodic(const Duration(seconds: 10), (_) async {
    if (lowVoltageTriggered) return;
    try {
      final voltages = await joint.readVoltage();
      final valid = voltages.where((v) => v > 0).toList();
      if (valid.isEmpty) return;
      final minV = valid.reduce((a, b) => a < b ? a : b);
      if (minV < lowVoltageThreshold) {
        lowVoltageTriggered = true;
        _log.severe(
          'LOW VOLTAGE: ${minV.toStringAsFixed(1)}V < ${lowVoltageThreshold}V — emergency sitDown',
        );
        m.add(const A.sitDown());
        Future<void>.delayed(const Duration(seconds: 4), () {
          joint.disable();
          motorOutputEnabled = false;
          _log.severe('Motors disabled due to low voltage');
        });
      }
    } catch (_) {}
  });

  if (_cfg.debugTui) {
    startDebugTui(imu: imu, joint: joint, m: m, arbiter: arbiter);
  }
}

Future<int> _resolveHistorySize(RobotProfile profile) async {
  final tensorSize = profile.toObservationBuilder().tensorSize;
  final inferred = await inferHistorySizeFromModel(
    modelPath: profile.modelPath,
    tensorSize: tensorSize,
  );
  if (inferred != null) {
    _log.info(
        'Inferred historySize=$inferred from model input '
        '(tensorSize=$tensorSize, model=${profile.modelPath})');
    return inferred;
  }

  _log.warning(
      'Unable to infer history size from model ${profile.modelPath}; '
      'falling back to 1');
  return 1;
}

Future<String> _resolveInputName(RobotProfile profile) async {
  final inferred = await inferInputNameFromModel(
    modelPath: profile.modelPath,
  );
  if (inferred != null && inferred.isNotEmpty) {
    _log.info(
      'Inferred inputName=$inferred from model ${profile.modelPath}',
    );
    return inferred;
  }

  _log.warning(
    'Unable to infer input name from model ${profile.modelPath}; '
    'falling back to "obs"',
  );
  return 'obs';
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
  const attempts = 8;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final received = joint.frequencyWatches.where((e) => e.value > 0).length;
    if (received == names.length) {
      _log.info('主动上报: 16/16 关节已收到 (attempt $attempt/$attempts)');
      return;
    }
    // Re-send reporting requests to wake slow motors up sooner.
    joint.setReporting(true);
  }
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
  required RealControlDog? controlDog,
  required RealController? controller,
  required RealImu imu,
  required Brain brain,
  required MotorHealthManager motorHealth,
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
      _jointForCleanup?.disable();
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
    for (final disposable in [motorHealth, arbiter, controlDog, controller, imu, joint, brain]) {
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
