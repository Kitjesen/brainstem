import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

/// Validates that enabling motor torque will begin from a settled, safe pose.
///
/// The four foot-wheel joints (indices 12-15) are intentionally exempt from
/// the absolute angle limit because they can rotate continuously.
abstract final class MotorEnableSafety {
  static const int legJointCount = 12;
  static const int minimumJointTelemetryHz = 50;
  static const double maxLegJointVelocityRadPerSec = 0.5;

  /// Indices of hip/thigh/calf telemetry in the raw CAN report order.
  ///
  /// Each leg reports `[hip, thigh, calf, foot]`; this differs from
  /// [JointsMatrix], whose four foot joints are stored after all 12 leg
  /// joints. Keep this mapping here so every hardware entry point validates
  /// the same 12 leg motors before torque is enabled.
  static const List<int> legCanTelemetryIndices = <int>[
    0,
    1,
    2,
    4,
    5,
    6,
    8,
    9,
    10,
    12,
    13,
    14,
  ];

  static bool hasFreshLegCanTelemetry(List<num> frequenciesHz) {
    return legCanTelemetryIndices.every(
      (index) =>
          index < frequenciesHz.length &&
          frequenciesHz[index].isFinite &&
          frequenciesHz[index] >= minimumJointTelemetryHz,
    );
  }

  /// Returns a human-readable reason when motor enable must be rejected.
  static String? blockReason({
    required S state,
    required JointsMatrix position,
    required JointsMatrix velocity,
    required double jointLimitRad,
    required bool hasFreshJointTelemetry,
    bool hasUnrecoveredMotorFaults = false,
    JointsMatrix? safePose,
    double? maxSafePoseErrorRad,
  }) {
    if (state is! Grounded) {
      return 'CMS must be Grounded before enabling motors '
          '(current: ${state.runtimeType})';
    }
    if (!hasFreshJointTelemetry) {
      return 'joint telemetry is not fresh enough';
    }
    if (hasUnrecoveredMotorFaults) {
      return 'motor fault recovery is pending';
    }
    if (!jointLimitRad.isFinite || jointLimitRad <= 0) {
      return 'configured joint limit is invalid';
    }
    if (position.hasNonFinite || velocity.hasNonFinite) {
      return 'joint position or velocity contains a non-finite value';
    }
    if ((safePose == null) != (maxSafePoseErrorRad == null)) {
      return 'safe grounded pose configuration is incomplete';
    }
    if (safePose != null) {
      if (safePose.hasNonFinite ||
          !maxSafePoseErrorRad!.isFinite ||
          maxSafePoseErrorRad <= 0) {
        return 'safe grounded pose configuration is invalid';
      }
    }

    for (var index = 0; index < legJointCount; index++) {
      final angle = position.values[index];
      if (angle.abs() > jointLimitRad) {
        return 'leg joint $index is outside the safe angle limit '
            '(${angle.toStringAsFixed(3)} rad)';
      }

      if (safePose != null &&
          (angle - safePose.values[index]).abs() > maxSafePoseErrorRad!) {
        return 'leg joint $index is outside the safe grounded pose window '
            '(${angle.toStringAsFixed(3)} rad)';
      }

      final speed = velocity.values[index];
      if (speed.abs() > maxLegJointVelocityRadPerSec) {
        return 'leg joint $index is still moving too fast '
            '(${speed.toStringAsFixed(3)} rad/s)';
      }
    }

    return null;
  }
}
