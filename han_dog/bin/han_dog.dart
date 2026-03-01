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
import 'package:han_dog/src/app/robot_params.dart';

final _log = Logger('han_dog');
final _cfg = HanDogConfig();

/// 所有需要在关机时取消的 subscription
final _subs = <StreamSubscription>[];

/// 用于异常退出时关闭 gRPC、释放端口
grpc.Server? _grpcServerForCleanup;

void main() {
  setupLogging();
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
  RealFrequency.manager.watch();

  _log.info('han_dog starting — $_cfg');

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
    await Future.delayed(const Duration(milliseconds: 100));
  }
  await _checkJointReporting(joint);

  // ──── 2. Brain + ONNX 模型 ─────────────────────────────────
  final brain = Brain(
    imu: imu,
    joint: joint,
    clock: clock,
    standingPose: standingPose,
    sittingPose: .zero(),
  );
  try {
    await brain.loadModel(_cfg.modelPath);
    _log.info('ONNX model loaded.');
  } catch (e) {
    _log.severe('Failed to load ONNX model: $e');
    joint.disable();
    imu.dispose();
    joint.dispose();
    return;
  }

  joint.kpExt = inferKp;
  joint.kdExt = inferKd;

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
  await m.stream.firstWhere((s) => s is Grounded);
  _log.info('CMS initialized: ${m.state}');

  final arbiter = ControlArbiter(m, timeout: _cfg.arbiterTimeout);
  _subs.add(arbiter.ownerStream.listen((owner) {
    _log.info('Arbiter control owner: ${owner ?? "none"}');
  }));

  // 推理输出 → 电机动作
  _subs.add(brain.nextActionStream.listen(
    (action) {
      // TODO: 验证数据流正常后取消注释以启用电机输出
      // joint.sendAction(action);
    },
    onError: (Object error, StackTrace st) {
      _log.severe('Inference stream error: $error', error, st);
      arbiter.fault('Inference stream error: $error');
    },
  ));

  // YUNZHUO 遥控器 → CMS 命令映射
  final controlDog = RealControlDog(
    brain: brain,
    imu: imu,
    joint: joint,
    arbiter: arbiter,
    inferKd: inferKd,
    inferKp: inferKp,
    standUpKd: standUpKd,
    standUpKp: standUpKp,
    sitDownKd: sitDownKd,
    sitDownKp: sitDownKp,
    controller: controller,
  );

  // ──── 4b. 策略管理 ────────────────────────────────────────
  final profiles = await loadProfiles(_cfg.profileDir);
  ProfileManager? profileManager;
  if (profiles.isNotEmpty) {
    profileManager = ProfileManager(
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: profiles.keys.first,
    );
    controlDog.onProfileSwitch = () => profileManager!.toggle();
    _log.info('ProfileManager ready: ${profiles.keys.join(", ")}');
  } else {
    _log.info('No profiles found in ${_cfg.profileDir}, running without ProfileManager');
  }

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
    startDebugTui(imu: imu, joint: joint, m: m);
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
  await Future.delayed(const Duration(seconds: 1));
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
      await Future.delayed(const Duration(seconds: 1));
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
    _log.info('Received $signal');

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
      _log.warning('Shutdown timeout, proceeding with disable.');
    } catch (e) {
      _log.warning('Shutdown error: $e, proceeding with disable.');
    }

    joint.disable();
    _log.info('Motors disabled safely.');

    await grpcServer.shutdown();
    _log.info('gRPC server stopped.');

    // 释放所有资源
    for (final sub in _subs) {
      try { sub.cancel(); } catch (_) {}
    }
    _subs.clear();
    getClockTimer()?.cancel();
    for (final disposable in [arbiter, controlDog, controller, imu, joint, brain]) {
      try { (disposable as dynamic).dispose(); } catch (_) {}
    }
    try { await m.close(); } catch (_) {}
    _log.info('All resources released.');
    exit(0);
  }

  _subs.add(ProcessSignal.sigint.watch().listen((s) => handle(s)));
  if (!Platform.isWindows) {
    _subs.add(ProcessSignal.sigterm.watch().listen((s) => handle(s)));
  }
}
