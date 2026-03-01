import 'dart:async';
import 'dart:io';

import 'package:frequency_watch/frequency_watch.dart';
import 'package:logging/logging.dart';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';

final _log = Logger('han_dog.monitoring');

const _jointNames = [
  'FR Hip', 'FR Thigh', 'FR Calf', 'FR Foot',
  'FL Hip', 'FL Thigh', 'FL Calf', 'FL Foot',
  'RR Hip', 'RR Thigh', 'RR Calf', 'RR Foot',
  'RL Hip', 'RL Thigh', 'RL Calf', 'RL Foot',
];

/// 传感器频率监控：首次降频时警告，连续 [threshold] 次低于 50Hz 时触发 Fault。
StreamSubscription<void> startSensorMonitoring({
  required RealImu imu,
  required RealJoint joint,
  required ControlArbiter arbiter,
  required int threshold,
}) {
  int lowCount = 0;
  return RealFrequency.manager.onTick.listen(
    (_) {
    if (imu.hz.value < 50 ||
        joint.frequencyWatches.any((e) => e.value < 50)) {
      lowCount++;
      if (lowCount == 1) {
        _log.warning('传感器频率降级 '
            '(IMU: ${imu.hz.value} Hz, '
            '关节: ${joint.frequencyWatches.map((e) => e.value).toList()})');
      } else if (lowCount == threshold) {
        final lowJoints = <String>[];
        for (var i = 0; i < joint.frequencyWatches.length; i++) {
          if (joint.frequencyWatches[i].value < 50) {
            lowJoints.add(
                '${_jointNames[i]}(${joint.frequencyWatches[i].value} Hz)');
          }
        }
        arbiter.fault('Sensor frequency too low for $lowCount ticks '
            '(IMU: ${imu.hz.value} Hz, '
            '低频关节: ${lowJoints.join(", ")})');
      }
    } else {
      if (lowCount > 0) {
        _log.info('传感器频率已恢复（持续低频 $lowCount 帧）');
      }
      lowCount = 0;
    }
  },
  onError: (Object error, StackTrace st) {
    _log.severe('Sensor monitoring tick error', error, st);
  });
}

/// 关节位置超限检测：任一关节超过 [limitRad] 时立即触发 Fault。
///
/// 使用关节频率 tick 驱动（与传感器监控共用时钟），减少额外开销。
/// 连续 [threshold] 次超限才报警（容忍单帧毛刺），超限即时 Fault。
StreamSubscription<void> startJointLimitMonitoring({
  required RealJoint joint,
  required ControlArbiter arbiter,
  required double limitRad,
}) {
  return RealFrequency.manager.onTick.listen(
    (_) {
      final pos = joint.position;
      final values = pos.values;
      for (var i = 0; i < values.length && i < _jointNames.length; i++) {
        final v = values[i];
        if (v.abs() > limitRad) {
          _log.severe('关节超限: ${_jointNames[i]}=${v.toStringAsFixed(3)} rad '
              '(limit=±$limitRad rad) — 触发 Fault');
          arbiter.fault('Joint ${_jointNames[i]} position=${v.toStringAsFixed(3)} '
              'exceeds limit ±$limitRad rad');
          return; // 一帧内只报一次
        }
      }
    },
    onError: (Object error, StackTrace st) {
      _log.severe('Joint limit monitoring tick error', error, st);
    },
  );
}

/// YUNZHUO 遥控器断连检测 + 自动重连。
StreamSubscription<void> startControllerMonitoring({
  required RealController controller,
  required ControlArbiter arbiter,
}) {
  int disconnectedTicks = 0;
  return RealFrequency.manager.onTick.listen((_) {
    if (controller.hz.value == 0) {
      disconnectedTicks++;
      if (disconnectedTicks == 1) {
        arbiter.fault('YUNZHUO controller disconnected (0 Hz)');
      }
      if (disconnectedTicks % 3 == 0) {
        _log.warning('Attempting to reopen controller...');
        if (controller.reopen()) {
          _log.info('Controller reconnected!');
          disconnectedTicks = 0;
        } else {
          _log.warning('Controller reconnect failed, will retry...');
        }
      }
    } else {
      if (disconnectedTicks > 0) {
        _log.info('Controller signal restored.');
      }
      disconnectedTicks = 0;
    }
  },
  onError: (Object error, StackTrace st) {
    _log.severe('Controller monitoring tick error', error, st);
  });
}

/// Debug TUI：实时打印 IMU + Joint 数据（每 500ms 刷新一次）。
///
/// [arbiter] 可选，传入后显示当前控制权归属。
Timer? startDebugTui({
  required RealImu imu,
  required RealJoint joint,
  required M m,
  ControlArbiter? arbiter,
}) {
  return Timer.periodic(const Duration(milliseconds: 500), (_) {
    final pos = joint.position;
    final gyro = imu.gyroscope;
    final grav = imu.projectedGravity;

    stdout.write('\x1B[2J\x1B[H');
    stdout.writeln('═══════════════ 实时传感器 (0.5s刷新) ═══════════════');
    stdout.writeln('');
    stdout.writeln('── IMU ───────────────────────────────────────');
    stdout.writeln('  角速度 (rad/s) : x=${gyro.x.toStringAsFixed(3)}, y=${gyro.y.toStringAsFixed(3)}, z=${gyro.z.toStringAsFixed(3)}');
    stdout.writeln('  重力向量       : x=${grav.x.toStringAsFixed(3)}, y=${grav.y.toStringAsFixed(3)}, z=${grav.z.toStringAsFixed(3)}');
    stdout.writeln('  频率           : ${_colorHz(imu.hz.value)}');
    stdout.writeln('');
    stdout.writeln('── 关节角度 (rad) ────────────────────────────');
    stdout.writeln('  FR: hip=${pos.frHip.toStringAsFixed(3)}, thigh=${pos.frThigh.toStringAsFixed(3)}, calf=${pos.frCalf.toStringAsFixed(3)}, foot=${pos.frFoot.toStringAsFixed(3)}');
    stdout.writeln('  FL: hip=${pos.flHip.toStringAsFixed(3)}, thigh=${pos.flThigh.toStringAsFixed(3)}, calf=${pos.flCalf.toStringAsFixed(3)}, foot=${pos.flFoot.toStringAsFixed(3)}');
    stdout.writeln('  RR: hip=${pos.rrHip.toStringAsFixed(3)}, thigh=${pos.rrThigh.toStringAsFixed(3)}, calf=${pos.rrCalf.toStringAsFixed(3)}, foot=${pos.rrFoot.toStringAsFixed(3)}');
    stdout.writeln('  RL: hip=${pos.rlHip.toStringAsFixed(3)}, thigh=${pos.rlThigh.toStringAsFixed(3)}, calf=${pos.rlCalf.toStringAsFixed(3)}, foot=${pos.rlFoot.toStringAsFixed(3)}');
    stdout.writeln('');
    stdout.writeln('── 频率 / 状态 ───────────────────────────────');
    stdout.writeln('  IMU: ${_colorHz(imu.hz.value)}');
    stdout.writeln('  关节: [${joint.frequencyWatches.map((e) => _colorHz(e.value)).join(", ")}]');
    stdout.writeln('  CMS: ${m.state}');
    if (arbiter != null) {
      final owner = arbiter.owner?.name ?? 'none';
      stdout.writeln('  控制权: $owner');
    }
    stdout.writeln('═══════════════════════════════════════════════');
  });
}

/// ANSI 频率颜色：≥45Hz 绿色，≥30Hz 黄色，<30Hz 红色。
String _colorHz(int hz) {
  if (hz >= 45) return '\x1B[32m$hz Hz\x1B[0m';
  if (hz >= 30) return '\x1B[33m$hz Hz\x1B[0m';
  return '\x1B[31m$hz Hz\x1B[0m';
}
