import 'dart:async';

import 'package:thunder_brain/thunder_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

import '../control_arbiter.dart';
import '../real_imu.dart';
import '../real_joint.dart';
import 'model_spec.dart';
import 'normal_recovery_runtime.dart';
import 'onnx_inference.dart';
import 'recovery.dart';

/// Shares the existing CAN/IMU instances. This class never opens a second device.
class HardwareRecovery {
  final _clock = Stopwatch()..start();
  final _reports = List<int?>.filled(16, null);
  int? _imuAt;
  final _subs = <StreamSubscription<Object?>>[];
  late final NormalRecoveryRuntime runtime;
  final OnnxRecoveryInference inference;

  HardwareRecovery._(this.inference);

  static Future<HardwareRecovery> create({
    required String configPath,
    required bool verified,
    required RealJoint joint,
    required RealImu imu,
    required ControlArbiter arbiter,
    required bool Function() enabled,
    required void Function(bool) setEnabled,
    required bool Function() canEnter,
    required bool Function() healthy,
    required List<double> lower,
    required List<double> upper,
  }) async {
    final spec = await RecoveryModelSpec.load(configPath);
    final inference = await OnnxRecoveryInference.start(
      spec.modelPath,
      expectedSha: spec.sha,
    );
    final result = HardwareRecovery._(inference);
    final normalKp = joint.kpExt, normalKd = joint.kdExt;
    var savedKp = normalKp, savedKd = normalKd;
    int now() => result._clock.elapsedMicroseconds;
    result._subs.add(
      joint.reportStream.listen(
        (event) {
          final leg = event.$1 ~/ 4, motor = event.$1 % 4;
          result._reports[motor == 3 ? 12 + leg : leg * 3 + motor] = now();
        },
        onError: (Object error, StackTrace stack) {
          result.runtime.interrupt('Joint stream failed');
        },
      ),
    );
    result._subs.add(
      imu.stateStream.listen(
        (values) {
          if (values.isNotEmpty) result._imuAt = now();
        },
        onError: (Object error, StackTrace stack) {
          result.runtime.interrupt('IMU stream failed');
        },
      ),
    );

    RecoverySample sample() {
      final at = now();
      var age = 0;
      var valid =
          healthy() && result._imuAt != null && at - result._imuAt! <= 100000;
      for (var i = 0; i < 16; i++) {
        final last = result._reports[i];
        final report = joint.getReport(i);
        if (last == null || report == null) {
          valid = false;
          continue;
        }
        final elapsed = (at - last) ~/ 1000;
        if (elapsed > age) age = elapsed;
        if (report.errors.value != 0 ||
            report.status.value == 1 ||
            report.status.value == 3 ||
            (enabled() && report.status.value != 2)) {
          valid = false;
        }
      }
      final gyro = imu.gyroscope, gravity = imu.projectedGravity;
      return RecoverySample(
        angular: [gyro.x, gyro.y, gyro.z],
        gravity: [gravity.x, gravity.y, gravity.z],
        q: joint.position.values,
        dq: joint.velocity.values,
        ageMs: age,
        healthy: valid,
      );
    }

    void send(RecoveryFrame frame) {
      joint.kpExt = JointsMatrix.fromList(frame.kp);
      joint.kdExt = JointsMatrix.fromList(frame.kd);
      joint.sendAction(JointsMatrix.fromList(frame.target));
    }

    Future<bool> waitForStatus(int status, int since) async {
      final deadline = now() + 1000000;
      while (now() < deadline) {
        if (List<bool>.generate(
          16,
          (i) =>
              result._reports[i] != null &&
              result._reports[i]! > since &&
              now() - result._reports[i]! <= 100000 &&
              joint.getReport(i)?.status.value == status,
        ).every((v) => v)) {
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return false;
    }

    result.runtime = NormalRecoveryRuntime(
      inference: inference,
      sample: sample,
      canEnter: () =>
          canEnter() && arbiter.state is Grounded && arbiter.owner == null,
      healthy: () =>
          healthy() && arbiter.state is Grounded && arbiter.owner == null,
      enabled: enabled,
      nowUs: now,
      verified: verified,
      lower: lower,
      upper: upper,
      enableHardware: (hold) async {
        savedKp = joint.kpExt;
        savedKd = joint.kdExt;
        final at = now();
        if (!result.runtime.live) {
          throw StateError('Recovery authority expired');
        }
        await joint.enable();
        if (!result.runtime.live) throw StateError('Recovery enable cancelled');
        send(hold);
        if (!await waitForStatus(2, at) || !result.runtime.live) {
          throw StateError('Motor enable unconfirmed');
        }
        sample().validate();
        setEnabled(true);
      },
      disableHardware: () async {
        setEnabled(false);
        final at = now();
        await joint.disable();
        return waitForStatus(0, at);
      },
      sendHardware: send,
      restoreNormalGains: () {
        joint.kpExt = savedKp;
        joint.kdExt = savedKd;
      },
    );
    return result;
  }

  Future<void> close() async {
    await runtime.shutdown();
    for (final sub in _subs) {
      await sub.cancel();
    }
    await inference.close();
  }
}
