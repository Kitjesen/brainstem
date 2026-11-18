import 'dart:async';
import 'dart:io';

import 'package:frequency_watch/frequency_watch.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:brainstem_api/brainstem_api.dart' as msg;
import 'package:logging/logging.dart';
import 'package:cms/cms.dart';
import 'package:thunder/src/app/config.dart';
import 'package:thunder/src/server/grpc_tls.dart';
import 'package:thunder/src/server/grpc_lan_development.dart';
import 'package:thunder/src/server/grpc_bind_retry.dart';
import 'package:thunder/src/app/monitoring.dart';
import 'package:thunder/src/app/local_controller.dart';
import 'package:thunder/src/web_controller.dart';
import 'package:thunder/src/web_control_runtime.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:thunder/src/recovery/hardware_recovery.dart';

final _log = Logger('thunder');
final _cfg = ThunderConfig();

const _bootMotorNames = [
  'FR Hip',
  'FR Thigh',
  'FR Calf',
  'FR Foot',
  'FL Hip',
  'FL Thigh',
  'FL Calf',
  'FL Foot',
  'RR Hip',
  'RR Thigh',
  'RR Calf',
  'RR Foot',
  'RL Hip',
  'RL Thigh',
  'RL Calf',
  'RL Foot',
];

/// 所有需要在关机时取消的 subscription
final _subs = <StreamSubscription<Object?>>[];

/// 用于异常退出时关闭 gRPC、释放端口
grpc.Server? _grpcServerForCleanup;

/// 用于异常退出时禁用电机
RealJoint? _jointForCleanup;

HardwareRecovery? _recoveryForCleanup;

WebController? _webForCleanup;
WebControlRuntime? _webRuntimeForCleanup;

/// 异常退出时先向机械臂发送安全中立包并关闭 UDP。
ArmTeleopBridge? _armBridgeForCleanup;

/// 策略热加载定时器（关机时取消）
Timer? _profileReloadTimer;

/// 本地手柄热插检测定时器（关机时取消）
Timer? _controllerHotplugTimer;

bool _hasJoystickNode(String preferredDevice) {
  if (File(preferredDevice).existsSync()) return true;
  final inputDir = Directory('/dev/input');
  if (!inputDir.existsSync()) return false;
  return inputDir.listSync().any(
    (entity) => entity.path.split('/').last.startsWith('js'),
  );
}

void main() {
  setupLogging(logDir: _cfg.logDir);
  runZonedGuarded(() async => _run(), (error, stack) {
    _log.severe('Uncaught: $error\n$stack');
    _controllerHotplugTimer?.cancel();
    (() async {
      try {
        _webRuntimeForCleanup?.dispose();
        await _webForCleanup?.close();
        await _armBridgeForCleanup?.dispose();
        await _recoveryForCleanup?.close();
        _jointForCleanup?.disable();
        await _grpcServerForCleanup?.shutdown();
        _log.info('gRPC port ${_cfg.grpcPort} released.');
      } catch (_) {}
      exit(1);
    })();
  });
}

Future<void> _run() async {
  Bloc.observer = SimpleBlocObserver(_log);
  final receiverObserveOnly =
      Platform.environment['THUNDER_RECEIVER_OBSERVE_ONLY']?.toLowerCase() ==
      'true';

  // ──── 0. 配置校验（前置检查）─────────────────────────────────
  final configErrors = _cfg.validate();
  if (configErrors.isNotEmpty) {
    for (final err in configErrors) {
      _log.severe('Config error: $err');
    }
    exit(1);
  }
  // Reject missing secrets/assets before opening any hardware.
  final webConfig = WebControlConfig.fromEnvironment(Platform.environment);

  RealFrequency.manager.watch();
  _log.info('thunder starting — $_cfg');

  // ──── 0b. 策略加载（必须先于一切设备初始化）───────────────────
  // RobotProfile 是所有机器人参数的唯一真相来源：
  // standingPose / sittingPose / kp / kd / modelPath 均来自此处。
  final profiles = await loadProfiles(_cfg.profileDir);
  if (profiles.isEmpty) {
    _log.severe(
      'No profiles found in "${_cfg.profileDir}" — '
      'cannot start without at least one profile. '
      'Create a JSON profile file and set THUNDER_PROFILE_DIR if needed.',
    );
    exit(1);
  }

  final OperatorModeSlots operatorSlots;
  try {
    operatorSlots = await OperatorModeSlots.load(_cfg.operatorModesPath);
    operatorSlots.validateProfiles(profiles);
  } catch (error, stack) {
    _log.severe(
      'Invalid operator modes ${_cfg.operatorModesPath}; no devices initialized',
      error,
      stack,
    );
    exit(1);
  }
  final defaultProfile = profiles[operatorSlots.defaultProfile]!;
  if (_cfg.defaultProfile != null &&
      _cfg.defaultProfile != defaultProfile.name) {
    _log.warning(
      'Ignoring legacy THUNDER_DEFAULT_PROFILE=${_cfg.defaultProfile}; operator modes boot in flat=${defaultProfile.name}',
    );
  }
  _log.info(
    'Operator modes config=${_cfg.operatorModesPath} flat=${operatorSlots.flat} stairs=${operatorSlots.stairs}; restart required to change bindings',
  );
  _log.info(
    'Default profile: ${defaultProfile.name} (model=${defaultProfile.modelPath})',
  );
  final historySize = await _resolveHistorySize(defaultProfile);
  final modelInputName = await _resolveInputName(defaultProfile);
  _log.info(
    'Resolved historySize=$historySize inputName=$modelInputName '
    '(model=${defaultProfile.modelPath})',
  );

  final clock = StreamController<void>.broadcast();

  // ──── 1. 设备初始化 ────────────────────────────────────────
  // Validate mixed transport topology before opening any serial device.
  final joint = createHardwareJoint();
  final imu = RealImu(_cfg.imuPort);
  final imuOpened = imu.open();
  if (!imuOpened) {
    _log.severe('IMU open failed on ${_cfg.imuPort}');
  } else {
    _log.info('IMU opened.');
  }

  final jointOpened = joint.open();
  _jointForCleanup = joint;
  if (!jointOpened) {
    _log.severe('Joint transport open failed');
  } else {
    _log.info(
      'Joint transport opened: ${Platform.environment['THUNDER_JOINT_TRANSPORT'] ?? 'pcan'}',
    );
  }
  validateThunderMotorLayout();
  _log.info('MOTOR_CODEC $thunderMotorCodecSummary');

  if (jointOpened) {
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
  }

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
    observationBuilder: defaultProfile.toObservationBuilder(),
    forceZeroWheelOnStop: defaultProfile.forceZeroWheelOnStop,
  );
  _log.info(
    'WHEEL_STOP profile=${defaultProfile.name} '
    'forceZeroWheelOnStop=${defaultProfile.forceZeroWheelOnStop}; hard-stop override retained',
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
        _log.severe(
          'Failed to load ONNX model after $modelLoadMaxAttempts attempts: $e',
        );
      } else {
        final delay = Duration(seconds: attempt * 2);
        _log.warning(
          'ONNX model load failed (attempt $attempt/$modelLoadMaxAttempts): $e — retrying in $delay',
        );
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

  brain.retainCurrentProfile(defaultProfile.name);
  brain.gestureLibrary = installOnboardGestures(defaultProfile.standingPose);
  _log.info(
    'Gesture catalog: '
    '${brain.gestureLibrary!.listedGestures.map((g) => g.name).join(', ')}',
  );
  try {
    for (final name in operatorSlots.profileNames) {
      if (name == defaultProfile.name) continue;
      final p = profiles[name]!;
      await brain.prepareProfile(
        name,
        modelPath: p.modelPath,
        observationBuilder: p.toObservationBuilder(),
        forceZeroWheelOnStop: p.forceZeroWheelOnStop,
      );
    }
    _log.info('R2 slots preloaded and warmed: ${operatorSlots.profileNames}');
  } catch (e, st) {
    _log.warning(
      'R2 preload failed; keep boot model, unavailable slot cannot be selected',
      e,
      st,
    );
  }

  joint.kpExt = defaultProfile.inferKp;
  joint.kdExt = defaultProfile.inferKd;
  final walkingKp = applyThunderWalkingHipKp(defaultProfile.inferKp);
  final walkingKd = applyThunderWalkingHipKdScale(defaultProfile.inferKd);
  _log.info(
    'HIP_KP walking=${_fmt4(walkingKp.frHip, walkingKp.flHip, walkingKp.rrHip, walkingKp.rlHip)} '
    'standUp=${_fmt4(defaultProfile.standUpKp.frHip, defaultProfile.standUpKp.flHip, defaultProfile.standUpKp.rrHip, defaultProfile.standUpKp.rlHip)} '
    'sitDown=${_fmt4(defaultProfile.sitDownKp.frHip, defaultProfile.sitDownKp.flHip, defaultProfile.sitDownKp.rrHip, defaultProfile.sitDownKp.rlHip)}',
  );
  _log.info(
    'HIP_KD walkingScale=$thunderWalkingHipKdScale '
    'walkingBase=${_fmt4(defaultProfile.inferKd.frHip, defaultProfile.inferKd.flHip, defaultProfile.inferKd.rrHip, defaultProfile.inferKd.rlHip)} '
    'walkingEffective=${_fmt4(walkingKd.frHip, walkingKd.flHip, walkingKd.rrHip, walkingKd.rlHip)} '
    'standUp=${_fmt4(defaultProfile.standUpKd.frHip, defaultProfile.standUpKd.flHip, defaultProfile.standUpKd.rrHip, defaultProfile.standUpKd.rlHip)} '
    'sitDown=${_fmt4(defaultProfile.sitDownKd.frHip, defaultProfile.sitDownKd.flHip, defaultProfile.sitDownKd.rrHip, defaultProfile.sitDownKd.rlHip)}',
  );

  // ──── 3. 手柄（YUNZHUO → Xbox → gRPC-only 三级降级）────────
  Gamepad? controller;
  WebController? webController;
  WebControlRuntime? webRuntime;
  // 预加载 Xbox 配置（供初始化和热插检测共用）
  XboxConfig xboxConfig = const XboxConfig();
  try {
    xboxConfig = await XboxConfig.loadFromFile(_cfg.xboxConfigPath);
    _log.info('Xbox config loaded: ${_cfg.xboxConfigPath}');
  } catch (_) {
    _log.fine('Xbox config not found, using defaults');
  }
  LocalControllerCandidate yunzhuoCandidate() {
    final yunzhuo = RealController(_cfg.yunzhuoPort);
    return (controller: yunzhuo, open: yunzhuo.open);
  }

  LocalControllerCandidate xboxCandidate() {
    final xbox = XboxNc500Controller(
      _cfg.xboxDevice,
      nc500HidrawDevice: _cfg.nc500HidrawDevice,
      config: xboxConfig,
    );
    return (controller: xbox, open: xbox.open);
  }

  if (webConfig != null) {
    webController = WebController(
      token: webConfig.token,
      assetsPath: webConfig.assetsPath,
      status: () => webRuntime?.snapshot() ?? WebControlRuntime.pendingStatus(),
      selectSlot: (slot) async {
        final runtime = webRuntime;
        if (runtime == null) throw StateError('Runtime initialization pending');
        await runtime.selectSlot(slot);
      },
      zeroAll: () async {
        final runtime = webRuntime;
        if (runtime == null) throw StateError('Runtime initialization pending');
        return runtime.zeroAll();
      },
    );
    _webForCleanup = webController;
    await webController.start(host: webConfig.host, port: webConfig.port);
    controller = webController;
    _log.info(
      'Web controller listening on ${webConfig.host}:${webController.boundPort}; runtime pending',
    );
  } else {
    controller = openLocalController(
      current: null,
      candidates: [yunzhuoCandidate, xboxCandidate],
    );
    if (controller != null) {
      _log.info(
        controller is RealController
            ? 'YUNZHUO controller opened.'
            : 'Xbox/NC500 controller opened.',
      );
    } else {
      _log.warning(
        'No controller available (YUNZHUO=${_cfg.yunzhuoPort}, Xbox/NC500=${_cfg.xboxDevice}) — '
        'running in gRPC-only mode',
      );
    }
  }

  // ──── 3a. 快速开机自检 + 统一使能互锁 ───────────────────────
  // 这里只检查当前硬件帧流，不做策略验收、模型参数验收或额外 PCAN 检查。
  final motorEnableInterlock = MotorEnableInterlock();
  Future<void> requestMotorEnable() async {
    if (Platform.environment['THUNDER_ALLOW_MOTOR_ENABLE']?.toLowerCase() !=
        'true') {
      throw StateError('Motor enable disabled by deployment policy');
    }
    await motorEnableInterlock.request(joint.enable);
  }

  final voice = QueuedVoiceAnnouncer(createVoiceAnnouncerFromEnvironment());
  final bootSelfCheck = BootSelfCheck(voice: voice);
  final inputHealth = controller is InputHealthGamepad
      ? controller as InputHealthGamepad
      : null;
  final selfCheckResult = await bootSelfCheck.run(
    CallbackBootSelfCheckProbe(() {
      final gyro = imu.gyroscope;
      final gravity = imu.projectedGravity;
      final motors = <MotorBootSnapshot>[];
      for (var i = 0; i < _bootMotorNames.length; i++) {
        final report = joint.latestReport(i);
        final lastReportAt = joint.latestReportAt(i);
        final hasReport = lastReportAt != null;
        final finite =
            hasReport &&
            report != null &&
            report.position.isFinite &&
            report.velocity.isFinite &&
            report.torque.isFinite &&
            report.temperature.isFinite;
        final hasError =
            !hasReport ||
            report == null ||
            report.status.value == 1 ||
            report.status.value == 3 ||
            report.errors.errors.isNotEmpty;
        motors.add(
          MotorBootSnapshot(
            name: _bootMotorNames[i],
            hasReport: hasReport,
            finite: finite,
            hasError: hasError,
            frameHz: joint.feedbackFrequency(i),
            lastFrameAt: lastReportAt,
          ),
        );
      }
      return BootSelfCheckSnapshot(
        imu: ImuBootSnapshot(
          deviceOpen: imuOpened,
          hasFrame: imu.lastUpdate != null,
          finite:
              gyro.x.isFinite &&
              gyro.y.isFinite &&
              gyro.z.isFinite &&
              gravity.x.isFinite &&
              gravity.y.isFinite &&
              gravity.z.isFinite,
          frameHz: imu.hz.value,
          lastFrameAt: imu.lastUpdate,
        ),
        motors: motors,
        controller: ControllerBootSnapshot(
          connected: inputHealth?.inputHealthy ?? false,
          hasFrame: inputHealth?.inputHealthy ?? false,
          frameHz: inputHealth?.inputHz ?? 0,
        ),
      );
    }),
  );
  if (selfCheckResult.motorEnableAllowed) {
    motorEnableInterlock.permit();
    if (selfCheckResult.passed) {
      _log.info('Boot self-check ready: motor enable permitted');
    } else {
      _log.warning(
        'Boot self-check has a recoverable controller fault; '
        'motor enable permitted while controller reconnects',
      );
    }
  } else {
    motorEnableInterlock.block(bootSelfCheck.blockReason ?? '开机自检失败');
    _log.severe(
      'Boot self-check fault: IMU/motor safety fault; '
      'motor enable remains blocked until process reboot',
    );
  }

  // ──── 4. FSM + 仲裁器 ──────────────────────────────────────
  final M m = M(brain)..add(Init());
  _subs.add(
    m.stream.listen((s) {
      _log.info('CMS state: $s');
    }),
  );
  try {
    await m.stream
        .firstWhere((s) => s is Grounded)
        .timeout(_cfg.startupTimeout);
  } on TimeoutException {
    _log.severe('FSM 未能在 ${_cfg.startupTimeoutSec}s 内到达 Grounded 状态 — 中止启动');
    await m.close();
    joint.disable();
    imu.dispose();
    joint.dispose();
    if (webController != null) {
      await webController.close();
    } else {
      controller?.dispose();
    }
    return;
  }
  _log.info('CMS initialized: ${m.state}');

  final arbiter = ControlArbiter(m, timeout: _cfg.arbiterTimeout);
  _subs.add(
    arbiter.ownerStream.listen((owner) {
      _log.info('Arbiter control owner: ${owner ?? "none"}');
    }),
  );
  // IMU 串口断联 → 记录警告。频率监控会在持续低频时触发 Fault。
  imu.onDisconnect = (reason) {
    _log.warning('IMU disconnect: $reason');
  };

  // ──── 4a. Motor health manager ─────────────────────────────
  final motorHealth = MotorHealthManager(
    joint: joint,
    requestFault: (reason) => arbiter.fault(reason),
    contextProvider: () {
      var vx = 0.0;
      var vy = 0.0;
      var yaw = 0.0;
      if (brain.histories.isNotEmpty) {
        final command = brain.histories.last.command;
        if (command case WalkCommand(:final direction)) {
          vx = direction.x;
          vy = direction.y;
          yaw = direction.z;
        }
      }
      return {
        'cmsState': m.state.runtimeType.toString(),
        'commandVx': vx,
        'commandVy': vy,
        'commandYaw': yaw,
      };
    },
  );
  _subs.add(
    motorHealth.healthStream.listen((event) {
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
    }),
  );
  // CMS state → recovery: when Grounded with faulted motors, attempt per-joint
  // verified recovery instead of blind clear-all.
  _subs.add(
    m.stream.listen((s) {
      if (_recoveryForCleanup?.runtime.selected != true &&
          s is Grounded &&
          motorHealth.hasFaults) {
        _log.info('Reached Grounded with faulted motors — starting recovery');
        motorHealth.recoverFaults();
      }
    }),
  );

  var motorOutputEnabled = false;
  var motorOutputVersion = 0;
  JointsMatrix? groundedHoldAction;
  var lastWheelActionLog = DateTime.fromMillisecondsSinceEpoch(0);

  void updateMotorOutputEnabled(bool enabled) {
    ++motorOutputVersion;
    motorOutputEnabled = enabled;
    if (!enabled && groundedHoldAction != null) {
      groundedHoldAction = null;
      _log.info('Grounded hold released: motor output disabled');
    }
  }

  void recordControlSample(JointsMatrix policyTarget, JointsMatrix sentTarget) {
    var vx = 0.0;
    var vy = 0.0;
    var yaw = 0.0;
    var gyro = <double>[0.0, 0.0, 0.0];
    if (brain.histories.isNotEmpty) {
      final history = brain.histories.last;
      if (history.command case WalkCommand(:final direction)) {
        vx = direction.x;
        vy = direction.y;
        yaw = direction.z;
      }
      gyro = [history.gyroscope.x, history.gyroscope.y, history.gyroscope.z];
    }
    motorHealth.recordControlSample(
      cmsState: arbiter.state.runtimeType.toString(),
      motorOutputEnabled: motorOutputEnabled,
      command: [vx, vy, yaw],
      policyTarget: policyTarget,
      sentTarget: sentTarget,
      position: joint.position,
      velocity: joint.velocity,
      hipTorque: [
        for (final i in const [0, 3, 6, 9]) joint.getReport(i)?.torque,
      ],
      gyroscope: gyro,
      inferenceUs: brain.lastInferenceUs,
    );
  }

  // 推理输出 → 电机动作 (gated through MotorHealthManager)
  _subs.add(
    brain.nextActionStream.listen(
      (action) {
        if (_recoveryForCleanup?.runtime.selected == true) {
          return;
        }
        if (!motorOutputEnabled) {
          groundedHoldAction = null;
          return;
        }

        if (arbiter.state is Grounded) {
          if (groundedHoldAction == null) {
            // Capture once on entry (or after re-enable). Re-reading the live
            // position every cycle turns position stiffness into damping and
            // lets suspended legs sag under gravity.
            groundedHoldAction = joint.position.discardFoot();
            _log.info(
              'Grounded hold latched: 12 leg joints fixed, wheel targets zero',
            );
          }
          recordControlSample(action, groundedHoldAction!);
          joint.sendAction(groundedHoldAction!);
          return;
        }

        if (groundedHoldAction != null) {
          groundedHoldAction = null;
          _log.info('Grounded hold released: leaving Grounded');
        }

        final gated = motorHealth.gateAction(action, joint.position);
        recordControlSample(action, gated);
        final now = DateTime.now();
        if (now.difference(lastWheelActionLog).inMilliseconds >= 100) {
          lastWheelActionLog = now;
          final v = joint.velocity;
          final p = joint.position;
          final h = brain.histories.last;
          var vx = 0.0;
          var vy = 0.0;
          var yaw = 0.0;
          if (h.command case WalkCommand(:final direction)) {
            vx = direction.x;
            vy = direction.y;
            yaw = direction.z;
          }
          final wheelTau = [
            for (var i = 12; i < 16; i++)
              joint.getReport(i)?.torque ?? double.nan,
          ];
          final hipTau = [
            for (final i in const [0, 3, 6, 9])
              joint.getReport(i)?.torque ?? double.nan,
          ];
          final thighTau = [
            for (final i in const [1, 4, 7, 10])
              joint.getReport(i)?.torque ?? double.nan,
          ];
          final calfTau = [
            for (final i in const [2, 5, 8, 11])
              joint.getReport(i)?.torque ?? double.nan,
          ];
          _log.info(
            'ACTION wheel target='
            'FR=${gated.frFoot.toStringAsFixed(2)} '
            'FL=${gated.flFoot.toStringAsFixed(2)} '
            'RR=${gated.rrFoot.toStringAsFixed(2)} '
            'RL=${gated.rlFoot.toStringAsFixed(2)} '
            'vel='
            'FR=${v.frFoot.toStringAsFixed(2)} '
            'FL=${v.flFoot.toStringAsFixed(2)} '
            'RR=${v.rrFoot.toStringAsFixed(2)} '
            'RL=${v.rlFoot.toStringAsFixed(2)} '
            'TRACE10 '
            'state=${arbiter.state.runtimeType} enabled=1 '
            'cmd=${_fmt3(vx, vy, yaw)} '
            'wheelErr=${_fmt4(gated.frFoot - v.frFoot, gated.flFoot - v.flFoot, gated.rrFoot - v.rrFoot, gated.rlFoot - v.rlFoot)} '
            'wheelTau=${_fmt4(wheelTau[0], wheelTau[1], wheelTau[2], wheelTau[3])} '
            'hipT=${_fmt4(gated.frHip, gated.flHip, gated.rrHip, gated.rlHip)} '
            'hipP=${_fmt4(p.frHip, p.flHip, p.rrHip, p.rlHip)} '
            'hipErr=${_fmt4(gated.frHip - p.frHip, gated.flHip - p.flHip, gated.rrHip - p.rrHip, gated.rlHip - p.rlHip)} '
            'hipV=${_fmt4(v.frHip, v.flHip, v.rrHip, v.rlHip)} '
            'hipTau=${_fmt4(hipTau[0], hipTau[1], hipTau[2], hipTau[3])} '
            'hipKd=${_fmt4(joint.kdExt.frHip, joint.kdExt.flHip, joint.kdExt.rrHip, joint.kdExt.rlHip)} '
            'thighT=${_fmt4(gated.frThigh, gated.flThigh, gated.rrThigh, gated.rlThigh)} '
            'thighP=${_fmt4(p.frThigh, p.flThigh, p.rrThigh, p.rlThigh)} '
            'thighErr=${_fmt4(gated.frThigh - p.frThigh, gated.flThigh - p.flThigh, gated.rrThigh - p.rrThigh, gated.rlThigh - p.rlThigh)} '
            'thighV=${_fmt4(v.frThigh, v.flThigh, v.rrThigh, v.rlThigh)} '
            'thighTau=${_fmt4(thighTau[0], thighTau[1], thighTau[2], thighTau[3])} '
            'calfT=${_fmt4(gated.frCalf, gated.flCalf, gated.rrCalf, gated.rlCalf)} '
            'calfP=${_fmt4(p.frCalf, p.flCalf, p.rrCalf, p.rlCalf)} '
            'calfErr=${_fmt4(gated.frCalf - p.frCalf, gated.flCalf - p.flCalf, gated.rrCalf - p.rrCalf, gated.rlCalf - p.rlCalf)} '
            'calfV=${_fmt4(v.frCalf, v.flCalf, v.rrCalf, v.rlCalf)} '
            'calfTau=${_fmt4(calfTau[0], calfTau[1], calfTau[2], calfTau[3])} '
            'gyro=${_fmt3(h.gyroscope.x, h.gyroscope.y, h.gyroscope.z)} '
            'gravity=${_fmt3(h.projectedGravity.x, h.projectedGravity.y, h.projectedGravity.z)} '
            'calfKp=${_fmt4(joint.kpExt.frCalf, joint.kpExt.flCalf, joint.kpExt.rrCalf, joint.kpExt.rlCalf)} '
            'calfKd=${_fmt4(joint.kdExt.frCalf, joint.kdExt.flCalf, joint.kdExt.rrCalf, joint.kdExt.rlCalf)} '
            'wheelKd=${_fmt4(joint.kdExt.frFoot, joint.kdExt.flFoot, joint.kdExt.rrFoot, joint.kdExt.rlFoot)} '
            'inferUs=${brain.lastInferenceUs}',
          );
        }
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
    ),
  );

  // YUNZHUO 遥控器 → CMS 命令映射（仅在遥控器可用时创建）
  RealControlDog? controlDog;
  ProfileManager? profileManager;
  UnifiedCmsServer? profileServer;
  if (controller != null &&
      !isReceiverObservation(controller, observeOnly: receiverObserveOnly)) {
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
      commandVxMax: defaultProfile.commandVxMax,
      commandVyMax: defaultProfile.commandVyMax,
      commandYawMax: defaultProfile.commandYawMax,
      forwardMinCommand: defaultProfile.forwardMinCommand,
      lateralMinCommand: defaultProfile.lateralMinCommand,
      yawMinCommand: defaultProfile.yawMinCommand,
      controller: controller,
      requestMotorEnable: requestMotorEnable,
    );

    // ──── 4b. 策略管理 ───────────────────────────────────────────
    profileManager = ProfileManager(
      voice: voice,
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: defaultProfile.name,
      operatorSlots: operatorSlots,
      onFault: (reason) {
        updateMotorOutputEnabled(false);
        joint.disable();
        arbiter.fault(reason);
      },
    );
    controlDog.onProfileSwitch = () => profileManager!.toggle();
    controlDog.onMotorEnableChanged = (enabled) {
      updateMotorOutputEnabled(enabled);
    };
    _log.info('ProfileManager ready: ${profiles.keys.join(", ")}');
  } else {
    _log.info(
      controller == null
          ? 'No controller — motor enable via gRPC only'
          : 'Receiver observe-only: RC actions are not bound',
    );
    final wiring = configureAppProfiles(
      voice: voice,
      brain: brain,
      joint: joint,
      profiles: profiles,
      initial: defaultProfile.name,
      operatorSlots: operatorSlots,
      states: arbiter.stateStream,
      controllerPresent: () => controlDog != null,
      onFault: (reason) {
        updateMotorOutputEnabled(false);
        joint.disable();
        arbiter.fault(reason);
      },
    );
    profileManager = wiring.manager;
    _subs.add(wiring.subscription);

    // ──── 本地手柄热插检测（每 3 秒扫描，云卓优先）───────────
    _controllerHotplugTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (controller != null) {
        _controllerHotplugTimer?.cancel();
        return;
      }
      if (!canAttachLocalController(
        grounded: arbiter.state is Grounded,
        motorOutputEnabled: motorOutputEnabled,
        motorEnablePending:
            controlDog?.motorEnablePending == true ||
            profileServer?.motorEnablePending == true,
        calibrationPending: profileServer?.calibrationPending == true,
        recoverySelected: _recoveryForCleanup?.runtime.selected == true,
        healthy:
            profileManager?.hasFault != true &&
            motorHealth.criticalJoints.isEmpty,
      )) {
        return;
      }
      final attached = openLocalController(
        current: controller,
        candidates: [
          if (File(_cfg.yunzhuoPort).existsSync()) yunzhuoCandidate,
          if (_hasJoystickNode(_cfg.xboxDevice)) xboxCandidate,
        ],
      );
      if (attached == null) return;
      _controllerHotplugTimer?.cancel();
      controller = attached;
      if (attached is RealController) {
        Timer(const Duration(seconds: 4), () {
          _log.info('YUNZHUO_REPORT_HZ ${attached.hz.value}');
        });
        _subs.add(
          startControllerMonitoring(controller: attached, arbiter: arbiter),
        );
      }
      if (isReceiverObservation(attached, observeOnly: receiverObserveOnly)) {
        _log.info(
          'Receiver hot-plugged in observe-only mode: RC actions are not bound',
        );
        return;
      }
      final activeProfile = profiles[profileManager!.currentName]!;
      _log.info(
        attached is RealController
            ? 'YUNZHUO hot-plugged.'
            : 'Xbox/NC500 hot-plugged.',
      );
      controlDog = RealControlDog(
        brain: brain,
        imu: imu,
        joint: joint,
        arbiter: arbiter,
        inferKd: activeProfile.inferKd,
        inferKp: activeProfile.inferKp,
        standUpKd: activeProfile.standUpKd,
        standUpKp: activeProfile.standUpKp,
        sitDownKd: activeProfile.sitDownKd,
        sitDownKp: activeProfile.sitDownKp,
        commandVxMax: activeProfile.commandVxMax,
        commandVyMax: activeProfile.commandVyMax,
        commandYawMax: activeProfile.commandYawMax,
        forwardMinCommand: activeProfile.forwardMinCommand,
        lateralMinCommand: activeProfile.lateralMinCommand,
        yawMinCommand: activeProfile.yawMinCommand,
        controller: attached,
        requestMotorEnable: requestMotorEnable,
      );
      final pm = ProfileManager(
        voice: voice,
        profiles: profiles,
        brain: brain,
        controlDog: controlDog!,
        initial: activeProfile.name,
        operatorSlots: operatorSlots,
        onFault: (reason) {
          updateMotorOutputEnabled(false);
          joint.disable();
          arbiter.fault(reason);
        },
      );
      profileManager = pm;
      profileServer?.profileManager = pm;
      controlDog!.onProfileSwitch = () => pm.toggle();
      controlDog!.onMotorEnableChanged = (enabled) {
        updateMotorOutputEnabled(enabled);
      };
      _profileReloadTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        pm.reload(_cfg.profileDir).catchError((Object e, StackTrace st) {
          _log.warning('Profile hot-reload failed', e, st);
        });
      });
      _log.info(
        'Controller hot-plug: ProfileManager ready: ${profiles.keys.join(", ")}',
      );
    });
  }

  // ──── 4c. 策略热加载（每 30s 扫描 profileDir）────────────────
  if (profileManager != null) {
    _profileReloadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      profileManager!.reload(_cfg.profileDir).catchError((
        Object e,
        StackTrace st,
      ) {
        _log.warning('Profile hot-reload failed', e, st);
      });
    });
  }

  // ──── 5. 监控 ──────────────────────────────────────────────
  _subs.add(
    startSensorMonitoring(
      imu: imu,
      joint: joint,
      arbiter: arbiter,
      threshold: _cfg.sensorLowThreshold,
    ),
  );
  Timer(const Duration(seconds: 4), () {
    _log.info(
      'MOTOR_REPORT_HZ '
      '${joint.frequencyWatches.map((watch) => watch.value).toList()}',
    );
  });
  final initialController = controller;
  if (initialController is RealController) {
    Timer(const Duration(seconds: 4), () {
      _log.info('YUNZHUO_REPORT_HZ ${initialController.hz.value}');
    });
    _subs.add(
      startControllerMonitoring(
        controller: initialController,
        arbiter: arbiter,
      ),
    );
  }
  _subs.add(
    startJointLimitMonitoring(
      joint: joint,
      arbiter: arbiter,
      limitRad: _cfg.jointLimitRad,
    ),
  );

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
    grpcLeaseTimeout: _cfg.grpcLeaseTimeout,
    hardwareMotionPeerAddresses: _cfg.grpcAllowedIps,
    developmentPlaintext: _cfg.grpcDevelopmentPlaintext,
    hardwareMotionPrincipals: _cfg.locomotionPrincipals,
    arbiter: arbiter,
    motor: joint,
    robotType: msg.RobotType.MINI,
    imuStreamFactory: () => imuBroadcast
        .expand((s) => s)
        .map(
          (s) => msg.Imu(
            gyroscope: msg.Vector3(
              x: s.gyroscope.x,
              y: s.gyroscope.y,
              z: s.gyroscope.z,
            ),
            quaternion: msg.Quaternion(
              w: s.quaternion.w,
              x: s.quaternion.x,
              y: s.quaternion.y,
              z: s.quaternion.z,
            ),
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
  profileServer = cmsService;
  cmsService.profileManager = profileManager;
  cmsService.joint = joint;
  cmsService.motorEnableBlockReason = () =>
      Platform.environment['THUNDER_ALLOW_MOTOR_ENABLE']?.toLowerCase() !=
          'true'
      ? 'Motor enable disabled by deployment policy'
      : motorEnableInterlock.allowed
      ? null
      : motorEnableInterlock.reason;
  cmsService.motorOutputEnabledProvider = () => motorOutputEnabled;
  cmsService.externalProfileContextProvider = () =>
      (motorOutputVersion, controlDog);
  cmsService.externalMotorEnablePendingProvider = () =>
      controlDog?.motorEnablePending ?? false;
  cmsService.criticalMotorFaultProvider = () =>
      motorHealth.criticalJoints.isNotEmpty;
  // 无遥控器时，gRPC Enable/Disable 直接控制 motorOutputEnabled
  cmsService.onMotorEnableChanged = (enabled) {
    updateMotorOutputEnabled(enabled);
    _log.info('motorOutputEnabled=$enabled (via gRPC)');
  };
  HardwareRecovery? recovery;
  final recoveryConfig = Platform.environment['THUNDER_RECOVERY_MODEL_CONFIG'];
  if (recoveryConfig != null && recoveryConfig.isNotEmpty) {
    try {
      recovery = await HardwareRecovery.create(
        configPath: recoveryConfig,
        verified:
            Platform.environment['THUNDER_NORMAL_RECOVERY_ENABLE_SEQUENCE_VERIFIED'] ==
            'true',
        joint: joint,
        imu: imu,
        arbiter: arbiter,
        enabled: () => motorOutputEnabled,
        setEnabled: updateMotorOutputEnabled,
        canEnter: () =>
            !motorOutputEnabled &&
            !profileManager!.hasFault &&
            controlDog?.motorEnablePending != true &&
            profileServer?.motorEnablePending != true &&
            profileServer?.calibrationPending != true,
        healthy: () =>
            !profileManager!.hasFault && motorHealth.criticalJoints.isEmpty,
        lower: defaultProfile.actionLowerLimits.values,
        upper: defaultProfile.actionUpperLimits.values,
      );
      _recoveryForCleanup = recovery;
      _log.info('RobotRecovery configured from $recoveryConfig');
    } catch (error, stack) {
      _log.severe(
        'RobotRecovery failed to load; continuing without it',
        error,
        stack,
      );
    }
  }
  cmsService.recovery = recovery?.runtime;
  // ──── 7. 信号处理 + 时钟 ───────────────────────────────────
  Timer? clockTimer;
  grpc.Server? grpcServer;
  var shuttingDown = false;
  _registerShutdown(
    m: m,
    joint: joint,
    arbiter: arbiter,
    cmsService: cmsService,
    getGrpcServer: () => grpcServer,
    onShutdown: () {
      shuttingDown = true;
      _controllerHotplugTimer?.cancel();
    },
    getControlDog: () => controlDog,
    getController: () => controller,
    imu: imu,
    brain: brain,
    motorHealth: motorHealth,
    armTeleopBridge: null,
    getClockTimer: () => clockTimer,
  );

  // Keep offline self-check announcements alive while DHCP is still pending.
  // Control clocks start only after the original restricted listener is ready.
  grpcServer = await bindWhenAddressAvailable(
    bind: () => _startGrpc(cmsService, _cfg),
    shouldStop: () => shuttingDown,
    onRetry: (error, attempt) {
      if (attempt == 1 || attempt % 15 == 0) {
        _log.warning(
          'gRPC waiting for configured address ${_cfg.grpcLanAddress}; '
          'attempt=$attempt; offline self-check voice remains active',
          error,
        );
      }
    },
  );
  if (grpcServer == null) return;
  _grpcServerForCleanup = grpcServer;
  if (shuttingDown) {
    await grpcServer.shutdown();
    return;
  }

  _log.info('Control service ready; receiverObserveOnly=$receiverObserveOnly.');

  clockTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    clock.add(null);
  });
  if (webController != null) {
    webRuntime = WebControlRuntime(
      brain: brain,
      joint: joint,
      imu: imu,
      arbiter: arbiter,
      controlDog: controlDog!,
      profileManager: profileManager!,
      slots: operatorSlots,
      profiles: profiles,
      interlock: motorEnableInterlock,
      motorOutputEnabled: () => motorOutputEnabled,
      allowMotorEnable:
          Platform.environment['THUNDER_ALLOW_MOTOR_ENABLE']?.toLowerCase() ==
          'true',
    );
    _webRuntimeForCleanup = webRuntime;
  }

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
          'LOW VOLTAGE: ${minV.toStringAsFixed(1)}V < ${lowVoltageThreshold}V — graceful sitDown',
        );
        // 先发 SitDown，等到 Grounded 再 disable（优雅着陆）
        m.add(const A.sitDown());
        () async {
          try {
            await m.stream
                .firstWhere((s) => s is Grounded)
                .timeout(const Duration(seconds: 8));
            _log.info('Low voltage: reached Grounded, disabling motors');
          } on TimeoutException {
            _log.severe('Low voltage: Grounded timeout 8s, force disabling');
          }
          joint.disable();
          updateMotorOutputEnabled(false);
          _log.severe('Motors disabled due to low voltage');
        }();
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
      '(tensorSize=$tensorSize, model=${profile.modelPath})',
    );
    return inferred;
  }

  _log.warning(
    'Unable to infer history size from model ${profile.modelPath}; '
    'falling back to 1',
  );
  return 1;
}

Future<String> _resolveInputName(RobotProfile profile) async {
  final inferred = await inferInputNameFromModel(modelPath: profile.modelPath);
  if (inferred != null && inferred.isNotEmpty) {
    _log.info('Inferred inputName=$inferred from model ${profile.modelPath}');
    return inferred;
  }

  _log.warning(
    'Unable to infer input name from model ${profile.modelPath}; '
    'falling back to "obs"',
  );
  return 'obs';
}

// ─── 辅助函数 ──────────────────────────────────────────────────

/// A failed bind must leave the process already owning the port untouched.
Future<grpc.Server> _startGrpc(
  UnifiedCmsServer cmsService,
  ThunderConfig config,
) async {
  final server = grpc.Server.create(
    services: [cmsService, cmsService.recoveryService],
    interceptors: config.grpcDevelopmentPlaintext
        ? [lanDevelopmentPeerInterceptor(config.grpcAllowedIps)]
        : const [],
    errorHandler: (error, trace) =>
        _log.severe('gRPC server error', error, trace),
  );

  final remoteMotionEnabled = config.grpcAllowedIps.isNotEmpty;
  final bindAddress = config.grpcDevelopmentPlaintext
      ? InternetAddress(config.grpcLanAddress)
      : remoteMotionEnabled
      ? InternetAddress.anyIPv4
      : InternetAddress.loopbackIPv4;
  final grpc.ServerCredentials? security = config.grpcMutualTlsEnabled
      ? MutualTlsServerCredentials(
          certificateFile: config.grpcTlsCertificateFile,
          privateKeyFile: config.grpcTlsPrivateKeyFile,
          clientCaFile: config.grpcTlsClientCaFile,
        )
      : null;

  try {
    await server.serve(
      address: bindAddress,
      port: config.grpcPort,
      security: security,
      requestClientCertificate: security != null,
      requireClientCertificate: security != null,
    );
  } catch (error, stackTrace) {
    try {
      await server.shutdown();
    } catch (cleanupError, cleanupStackTrace) {
      _log.warning(
        'Failed gRPC server cleanup',
        cleanupError,
        cleanupStackTrace,
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  _log.info(
    'gRPC server listening on ${bindAddress.address}:${config.grpcPort} '
    '(${config.grpcDevelopmentPlaintext
        ? "development plaintext"
        : security == null
        ? "loopback h2c"
        : "mutual TLS"})',
  );
  return server;
}

/// 注册 SIGINT/SIGTERM 处理：安全坐下 → 禁用电机 → 释放资源。
void _registerShutdown({
  required M m,
  required RealJoint joint,
  required ControlArbiter arbiter,
  required UnifiedCmsServer cmsService,
  required grpc.Server? Function() getGrpcServer,
  required void Function() onShutdown,
  required RealControlDog? Function() getControlDog,
  required Gamepad? Function() getController,
  required RealImu imu,
  required Brain brain,
  required MotorHealthManager motorHealth,
  required ArmTeleopBridge? armTeleopBridge,
  required Timer? Function() getClockTimer,
}) {
  var shuttingDown = false;

  Future<void> handle(ProcessSignal signal) async {
    if (shuttingDown) return;
    shuttingDown = true;
    onShutdown();
    _recoveryForCleanup?.runtime.interrupt('Process signal $signal');
    _log.info('Received $signal — starting graceful shutdown');
    // 全局关机总超时：防止任意步骤挂起导致进程永久卡死
    const hardDeadline = Duration(seconds: 15);
    Timer(hardDeadline, () {
      _log.severe(
        'Shutdown exceeded ${hardDeadline.inSeconds}s hard deadline — forcing exit(1)',
      );
      _jointForCleanup?.disable();
      exit(1);
    });

    try {
      _webRuntimeForCleanup?.dispose();
      await _webForCleanup?.close().timeout(const Duration(seconds: 3));
      await armTeleopBridge?.dispose();
      _armBridgeForCleanup = null;

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

    try {
      await _recoveryForCleanup?.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _recoveryForCleanup = null;

    await joint.disable();
    if (joint.lastDisableConfirmed) {
      _log.info('Motors disabled safely (feedback verified).');
    } else {
      _log.severe(
        'Shutdown with UNCONFIRMED motor disable: '
        '${joint.unconfirmedDisableJoints}',
      );
    }

    try {
      cmsService.dispose();
      await getGrpcServer()?.shutdown().timeout(const Duration(seconds: 3));
      _log.info('gRPC server stopped.');
    } on TimeoutException {
      _log.warning('gRPC shutdown timed out — continuing.');
    }

    // 释放所有资源
    for (final sub in _subs) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _subs.clear();
    getClockTimer()?.cancel();
    _profileReloadTimer?.cancel();
    _controllerHotplugTimer?.cancel();
    for (final disposable in [
      motorHealth,
      arbiter,
      getControlDog(),
      getController(),
      imu,
      joint,
      brain,
    ]) {
      try {
        (disposable as dynamic).dispose();
      } catch (_) {}
    }
    try {
      await m.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _log.info('All resources released — exit(0)');
    exit(0);
  }

  _subs.add(ProcessSignal.sigint.watch().listen((s) => handle(s)));
  if (!Platform.isWindows) {
    _subs.add(ProcessSignal.sigterm.watch().listen((s) => handle(s)));
  }
}

String _fmt3(double a, double b, double c) =>
    '[${a.toStringAsFixed(3)},${b.toStringAsFixed(3)},${c.toStringAsFixed(3)}]';

String _fmt4(double a, double b, double c, double d) =>
    '[${a.toStringAsFixed(3)},${b.toStringAsFixed(3)},${c.toStringAsFixed(3)},${d.toStringAsFixed(3)}]';

({ProfileManager manager, StreamSubscription<S> subscription})
configureAppProfiles({
  required Brain brain,
  required RealJoint joint,
  required Map<String, RobotProfile> profiles,
  required String initial,
  required OperatorModeSlots operatorSlots,
  required Stream<S> states,
  required bool Function() controllerPresent,
  required void Function(String) onFault,
  VoiceAnnouncer? voice,
}) {
  final profile =
      profiles[initial] ?? (throw ArgumentError.value(initial, 'initial'));
  final gains = GainManager(
    inferKp: profile.inferKp,
    inferKd: profile.inferKd,
    standUpKp: profile.standUpKp,
    standUpKd: profile.standUpKd,
    sitDownKp: profile.sitDownKp,
    sitDownKd: profile.sitDownKd,
    onChanged: (kp, kd) {
      joint.kpExt = kp;
      joint.kdExt = kd;
    },
  );
  final manager = ProfileManager(
    profiles: profiles,
    brain: brain,
    gains: gains,
    initial: initial,
    operatorSlots: operatorSlots,
    onFault: onFault,
    voice: voice,
  );
  final subscription = states.listen(
    (state) {
      if (!controllerPresent()) gains.applyState(state);
    },
    onError: (Object error, StackTrace trace) {
      _log.severe('App profile state stream failed', error, trace);
      onFault('App profile state stream failed');
    },
  );
  return (manager: manager, subscription: subscription);
}
