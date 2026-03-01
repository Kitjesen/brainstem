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

/// 传感器频率监控：连续 [threshold] 次低于 50Hz 时触发 Fault。
StreamSubscription<void> startSensorMonitoring({
  required RealImu imu,
  required RealJoint joint,
  required ControlArbiter arbiter,
  required int threshold,
}) {
  int lowCount = 0;
  return RealFrequency.manager.onTick.listen((_) {
    if (imu.hz.value < 50 ||
        joint.frequencyWatches.any((e) => e.value < 50)) {
      lowCount++;
      if (lowCount == threshold) {
        final lowJoints = <String>[];
        for (var i = 0; i < joint.frequencyWatches.length; i++) {
          if (joint.frequencyWatches[i].value < 50) {
            lowJoints.add(
                '${_jointNames[i]}(${joint.frequencyWatches[i].value} Hz)');
          }
        }
        arbiter.fault('Sensor frequency too low for $lowCount ticks '
            '(IMU: ${imu.hz.value} Hz, '
            'Joints: ${joint.frequencyWatches.map((e) => e.value).toList()}, '
            '0/低频: ${lowJoints.join(", ")})');
      }
    } else {
      lowCount = 0;
    }
  });
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
  });
}

/// Debug TUI：实时打印 IMU + Joint 数据（每 500ms 刷新一次）。
Timer? startDebugTui({
  required RealImu imu,
  required RealJoint joint,
  required M m,
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
    stdout.writeln('  频率           : ${imu.hz.value} Hz');
    stdout.writeln('');
    stdout.writeln('── 关节角度 (rad) ────────────────────────────');
    stdout.writeln('  FR: hip=${pos.frHip.toStringAsFixed(3)}, thigh=${pos.frThigh.toStringAsFixed(3)}, calf=${pos.frCalf.toStringAsFixed(3)}, foot=${pos.frFoot.toStringAsFixed(3)}');
    stdout.writeln('  FL: hip=${pos.flHip.toStringAsFixed(3)}, thigh=${pos.flThigh.toStringAsFixed(3)}, calf=${pos.flCalf.toStringAsFixed(3)}, foot=${pos.flFoot.toStringAsFixed(3)}');
    stdout.writeln('  RR: hip=${pos.rrHip.toStringAsFixed(3)}, thigh=${pos.rrThigh.toStringAsFixed(3)}, calf=${pos.rrCalf.toStringAsFixed(3)}, foot=${pos.rrFoot.toStringAsFixed(3)}');
    stdout.writeln('  RL: hip=${pos.rlHip.toStringAsFixed(3)}, thigh=${pos.rlThigh.toStringAsFixed(3)}, calf=${pos.rlCalf.toStringAsFixed(3)}, foot=${pos.rlFoot.toStringAsFixed(3)}');
    stdout.writeln('');
    stdout.writeln('── 频率 ──────────────────────────────────────');
    stdout.writeln('  IMU: ${imu.hz.value} Hz');
    stdout.writeln('  关节: ${joint.frequencyWatches.map((e) => e.value).toList()}');
    stdout.writeln('  CMS: ${m.state}');
    stdout.writeln('═══════════════════════════════════════════════');
  });
}
