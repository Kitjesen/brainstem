import 'dart:async';
import 'dart:io';

import 'package:thunder_brain/thunder_brain.dart';
import 'package:logging/logging.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

import 'app/actuator_feedback_freshness.dart';
import 'app/boot_self_check.dart';
import 'app/operator_mode_slots.dart';
import 'app/profile_manager.dart';
import 'app/robot_profile.dart';
import 'control_arbiter.dart';
import 'real_control_dog.dart';
import 'real_imu.dart';
import 'real_joint.dart';
import 'web_zero_stability.dart';

final _zeroLog = Logger('thunder.web_zero');

/// Validated before device initialization; no direct environment secret fallback.
class WebControlConfig {
  final String token;
  final String assetsPath;
  final String host;
  final int port;

  const WebControlConfig._(this.token, this.assetsPath, this.host, this.port);

  static WebControlConfig? fromEnvironment(Map<String, String> env) {
    if (env['THUNDER_WEB_CONTROL_ENABLED'] != 'true') return null;
    final path = env['THUNDER_WEB_TOKEN_FILE']?.trim();
    if (path == null ||
        path.isEmpty ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError('Web control requires a regular private token file');
    }
    final file = File(path);
    final stat = file.statSync();
    if (!Platform.isWindows && stat.mode & 0x3f != 0) {
      throw StateError('Web token file must not grant group/other permissions');
    }
    if (stat.size > 4096) throw StateError('Web token file is too large');
    final token = file.readAsStringSync().trim();
    if (token.length < 24) {
      throw StateError('Web token must contain at least 24 characters');
    }
    final host = (env['THUNDER_WEB_HOST'] ?? '0.0.0.0').trim();
    final port = int.tryParse(env['THUNDER_WEB_PORT'] ?? '8088');
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      throw StateError('Invalid web listen address/port');
    }
    final assets = env['THUNDER_WEB_ASSETS'] ?? 'thunder/web';
    for (final name in ['index.html', 'app.js', 'styles.css']) {
      if (!File('$assets/$name').existsSync()) {
        throw StateError('Missing web asset: $name');
      }
    }
    return WebControlConfig._(token, assets, host, port);
  }

  static InternetAddress grpcAddress({required bool webEnabled}) =>
      webEnabled ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4;
}

class WebControlRuntime {
  final Brain brain;
  final RealJoint joint;
  final RealImu imu;
  final ControlArbiter arbiter;
  final RealControlDog controlDog;
  final ProfileManager profileManager;
  final OperatorModeSlots slots;
  final Map<String, RobotProfile> profiles;
  final MotorEnableInterlock interlock;
  final bool Function() motorOutputEnabled;
  final bool allowMotorEnable;
  final DateTime Function() now;
  final Duration zeroTimeout;
  final Duration zeroPoll;
  final Duration zeroStableFor;
  late final ZeroStabilityWindow _zeroStability;
  late final StreamSubscription<(int, RSStateReport)> _zeroReports;
  var _zeroPhase = 'waiting';
  bool _busy = false;
  bool _disposed = false;

  WebControlRuntime({
    required this.brain,
    required this.joint,
    required this.imu,
    required this.arbiter,
    required this.controlDog,
    required this.profileManager,
    required this.slots,
    required Map<String, RobotProfile> profiles,
    required this.interlock,
    required this.motorOutputEnabled,
    required this.allowMotorEnable,
    this.now = DateTime.now,
    this.zeroTimeout = const Duration(seconds: 2),
    this.zeroPoll = const Duration(milliseconds: 25),
    this.zeroStableFor = const Duration(milliseconds: 500),
    DateTime Function()? zeroClock,
  }) : profiles = Map.unmodifiable(profiles) {
    _zeroStability = ZeroStabilityWindow(
      window: zeroStableFor,
      clock: zeroClock,
    );
    _zeroReports = joint.reportStream.listen(
      (event) {
        final report = event.$2;
        _zeroStability.record(
          event.$1,
          position: report.position,
          velocity: report.velocity,
          healthy:
              report.status == RSStatus.reset &&
              report.errors.errors.isEmpty &&
              report.torque.isFinite &&
              report.temperature.isFinite,
        );
      },
      onError: (Object error) => _zeroStability.clear(),
      onDone: _zeroStability.clear,
    );
  }

  static Map<String, Object?> pendingStatus() => {
    'ready': false,
    'preview': false,
    'cms': 'PENDING',
    'motor_enabled': false,
    'hardware_state_unknown': true,
    'can_enable': false,
    'can_switch': false,
    'can_zero': false,
    'can_open_zero': false,
    'zero_block_reason': '控制程序尚未就绪',
    'zero_phase': 'waiting',
    'busy': false,
    'block_reason': 'Runtime initialization pending',
    'motors': <Object?>[],
  };

  bool _fresh(int id, DateTime at) {
    final stamp = joint.latestReportAt(id);
    if (stamp == null) return false;
    final age = at.difference(stamp);
    return !age.isNegative && age <= defaultActuatorFeedbackMaxAge;
  }

  bool _healthy(int id, DateTime at) {
    final r = joint.latestReport(id);
    return _fresh(id, at) &&
        r != null &&
        r.position.isFinite &&
        r.velocity.isFinite &&
        r.torque.isFinite &&
        r.temperature.isFinite &&
        r.errors.errors.isEmpty &&
        (r.status == RSStatus.reset || r.status == RSStatus.motor);
  }

  bool _allReset(DateTime at) => List.generate(16, (id) => id).every(
    (id) =>
        _healthy(id, at) && joint.latestReport(id)!.status == RSStatus.reset,
  );

  String? _zeroSafetyBlockReason() {
    if (_disposed) return '控制程序已关闭';
    if (arbiter.state is! Grounded || arbiter.profileSwitchInProgress) {
      return '需趴地且不处于姿态或策略切换中';
    }
    if (motorOutputEnabled()) return '请先断使能';
    final at = now();
    for (var id = 0; id < 16; id++) {
      final name =
          '${['FR', 'FL', 'RR', 'RL'][id < 12 ? id ~/ 3 : id - 12]} '
          '${id < 12 ? ['Hip', 'Thigh', 'Calf'][id % 3] : 'Foot'}';
      if (!_healthy(id, at)) return '电机反馈缺失、过期或报警：$name';
      if (joint.latestReport(id)!.status != RSStatus.reset) {
        return '电机尚未确认断使能：$name';
      }
    }
    return null;
  }

  String? _zeroReadyBlockReason() =>
      _zeroSafetyBlockReason() ??
      (arbiter.isHandlingEvent
          ? '等待控制操作完成'
          : !joint.canZeroWriteImmediately
          ? '等待CAN发送队列空闲；未写入零点'
          : _zeroStability.blockReason());

  Map<String, Object?> snapshot() {
    if (_disposed) return pendingStatus();
    final at = now();
    final current = profileManager.currentName;
    final profile = profiles[current];
    if (profile == null) throw StateError('Unknown active profile');
    final healthy = List.generate(16, (id) => _healthy(id, at));
    final allHealthy = healthy.every((value) => value);
    final allEnabled =
        allHealthy &&
        List.generate(
          16,
          (id) => joint.latestReport(id)!.status == RSStatus.motor,
        ).every((value) => value);
    final allReset = _allReset(at);
    final gyro = imu.gyroscope;
    final gravity = imu.projectedGravity;
    final imuHealthy =
        !imu.isStale &&
        [
          gyro.x,
          gyro.y,
          gyro.z,
          gravity.x,
          gravity.y,
          gravity.z,
        ].every((v) => v.isFinite);
    final busy =
        _busy || arbiter.profileSwitchInProgress || arbiter.isHandlingEvent;
    final zeroSafetyReason = _zeroSafetyBlockReason();
    final zeroReason = _busy
        ? switch (_zeroPhase) {
            'writing' => '正在写入零点，请勿挪动',
            'verifying' => '正在验证零点，请勿挪动',
            _ => '上一项操作尚未完成',
          }
        : _zeroReadyBlockReason();
    final String? blockReason = !interlock.allowed
        ? interlock.reason
        : !allowMotorEnable
        ? 'THUNDER_ALLOW_MOTOR_ENABLE is not true'
        : !allHealthy
        ? 'Motor feedback missing, stale or faulted'
        : !imuHealthy
        ? 'IMU feedback missing, stale or invalid'
        : !allEnabled && !allReset
        ? 'Motor enable state is inconsistent'
        : busy
        ? 'Control operation in progress'
        : arbiter.state is Zero || arbiter.state is Transitioning
        ? 'CMS is not ready for enable'
        : null;
    var command = <double>[0, 0, 0];
    if (brain.histories.isNotEmpty) {
      if (brain.histories.last.command case WalkCommand(:final direction)) {
        command = [direction.x, direction.y, direction.z];
      }
    }
    return {
      'ready': true,
      'preview': false,
      'cms': arbiter.state.runtimeType.toString().toUpperCase(),
      'motor_enabled': allEnabled,
      'motor_output_enabled': motorOutputEnabled(),
      'hardware_state_unknown':
          !allHealthy || !imuHealthy || (!allEnabled && !allReset),
      'can_enable': blockReason == null,
      'can_switch':
          !busy && allEnabled && imuHealthy && controlDog.canSwitchProfile,
      'can_open_zero': !_busy && zeroSafetyReason == null,
      'can_zero': !busy && zeroReason == null,
      'zero_block_reason': zeroReason,
      'zero_phase': _busy
          ? _zeroPhase
          : (zeroReason == null ? 'ready' : 'waiting'),
      'busy': busy,
      'block_reason': blockReason,
      'model_slot': current == slots.flat
          ? 'flat'
          : current == slots.stairs
          ? 'stairs'
          : current == slots.highPlatform && slots.highPlatform != null
          ? 'high_platform'
          : null,
      'model_profile': current,
      'slots': {
        'flat': slots.flat,
        'stairs': slots.stairs,
        if (slots.highPlatform != null) 'high_platform': slots.highPlatform,
      },
      'limits': {
        'vx': profile.commandVxMax,
        'vy': profile.commandVyMax,
        'yaw': profile.commandYawMax,
      },
      'minimums': {
        'vx': profile.forwardMinCommand,
        'vy': profile.lateralMinCommand,
        'yaw': profile.yawMinCommand,
      },
      'deadzone': 0.1,
      'command': [for (final value in command) value.isFinite ? value : null],
      'motors': [
        for (var id = 0; id < 16; id++)
          {
            'id': id,
            'leg': ['FR', 'FL', 'RR', 'RL'][id < 12 ? id ~/ 3 : id - 12],
            'joint': id < 12 ? ['Hip', 'Thigh', 'Calf'][id % 3] : 'Foot',
            'online': _fresh(id, at),
            'status': joint.latestReport(id)?.status.value ?? 3,
            'position':
                _fresh(id, at) && joint.latestReport(id)!.position.isFinite
                ? joint.latestReport(id)!.position
                : null,
            'errors': [
              for (final error
                  in joint.latestReport(id)?.errors.errors ?? <RSError>{})
                error.name,
            ],
          },
      ],
    };
  }

  Future<void> selectSlot(String slot) async {
    final target = switch (slot) {
      'flat' => slots.flat,
      'stairs' => slots.stairs,
      'high_platform' =>
        slots.highPlatform ??
            (throw StateError('High platform slot is unassigned')),
      _ => throw ArgumentError('Unknown operator slot: $slot'),
    };
    if (snapshot()['can_switch'] != true) {
      throw StateError('Model selection requires the existing R2 switch gate');
    }
    if (profileManager.currentName == target) return;
    final names = slots.profileNames;
    final index = names.indexOf(profileManager.currentName);
    if (index < 0 || names[(index + 1) % names.length] != target) {
      throw StateError('Requested slot is not the next R2 mode');
    }
    _busy = true;
    try {
      await controlDog.requestProfileSwitch();
      if (profileManager.currentName != target) {
        throw StateError('Profile switch did not commit the requested slot');
      }
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Object?>> zeroAll() async {
    final reason = _zeroReadyBlockReason();
    if (_busy || reason != null) {
      throw ZeroNotStarted(reason ?? '上一项操作尚未完成');
    }
    _busy = true;
    _zeroPhase = 'writing';
    try {
      _zeroLog.warning('Explicit zero write requested for 16 disabled motors');
      if (!await joint.setZero()) throw StateError('Zero write was rejected');
      final afterWrite = now();
      _zeroStability.clear();
      _zeroPhase = 'verifying';
      final elapsed = Stopwatch()..start();
      while (elapsed.elapsed < zeroTimeout) {
        await Future<void>.delayed(zeroPoll);
        final blocked = _zeroSafetyBlockReason();
        if (blocked != null) throw StateError(blocked);
        final verified = List.generate(16, (id) => id).every(
          (id) =>
              joint.latestReportAt(id)!.isAfter(afterWrite) &&
              joint.latestReport(id)!.position.abs() <= 0.01,
        );
        if (verified && _zeroStability.blockReason() == null) {
          _zeroLog.info(
            'Fresh stable zero feedback verified for all 16 motors',
          );
          return {
            'verified': 16,
            'save_requested': true,
            'power_cycle_verified': false,
            'positions': [
              for (var id = 0; id < 16; id++) joint.latestReport(id)!.position,
            ],
          };
        }
      }
      throw TimeoutException(
        'Fresh stable zero feedback was not verified for all 16 motors',
        zeroTimeout,
      );
    } catch (error, stack) {
      _zeroLog.severe(
        'Zero write attempted; result unconfirmed: $error',
        error,
        stack,
      );
      rethrow;
    } finally {
      _busy = false;
      _zeroPhase = 'waiting';
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_zeroReports.cancel());
  }
}
