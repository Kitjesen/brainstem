import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

import 'common.dart';

/// 将一帧 [History] 编码为 ONNX 输入张量。
/// 封装：特征选择 / 归一化 / 缩放 / 张量布局。
abstract interface class ObservationBuilder {
  /// 每帧张量维度（用于 ONNX shape 验证）。
  int get tensorSize;

  /// 将一帧 [History] 编码为长度 [tensorSize] 的 `List<double>`。
  List<double> build(History h);

  /// action 缩放因子（Walk 用于 toRealAction / fromRealAction）。
  (double, double, double, double) get actionScale;

  /// 站立姿态（Walk 用于 toRealAction / fromRealAction 以及 StandUp 目标姿态）。
  JointsMatrix get standingPose;
  JointsMatrix get actionLowerLimits;
  JointsMatrix get actionUpperLimits;
}

/// 标准 57 维观测构建器：
/// [gyroscope(3), projectedGravity(3), direction(3),
///  jointPosition(16), jointVelocity(16), action(16)]
class StandardObservationBuilder implements ObservationBuilder {
  static final JointsMatrix defaultActionLowerLimits = JointsMatrix.fromList([
    -0.39,
    -3.12,
    0.02,
    -0.39,
    0.02,
    -3.12,
    -0.39,
    0.02,
    -3.12,
    -0.39,
    -3.12,
    -3.12,
    -35.0,
    -35.0,
    -35.0,
    -35.0,
  ]);

  static final JointsMatrix defaultActionUpperLimits = JointsMatrix.fromList([
    0.39,
    -0.02,
    3.12,
    0.39,
    3.12,
    -0.02,
    0.39,
    3.12,
    3.12,
    0.39,
    -0.02,
    3.12,
    35.0,
    35.0,
    35.0,
    35.0,
  ]);

  @override
  final (double, double, double, double) actionScale;

  @override
  final JointsMatrix standingPose;

  @override
  final JointsMatrix actionLowerLimits;

  @override
  final JointsMatrix actionUpperLimits;

  final double imuGyroscopeScale;
  final (double, double, double, double) jointVelocityScale;

  StandardObservationBuilder({
    required this.standingPose,
    JointsMatrix? actionLowerLimits,
    JointsMatrix? actionUpperLimits,
    this.imuGyroscopeScale = 0.25,
    this.jointVelocityScale = (0.05, 0.05, 0.05, 0.05),
    this.actionScale = (0.125, 0.25, 0.25, 5.0),
  }) : actionLowerLimits = actionLowerLimits ?? defaultActionLowerLimits,
       actionUpperLimits = actionUpperLimits ?? defaultActionUpperLimits;

  @override
  int get tensorSize => 3 + 3 + 3 + 16 + 16 + 16; // 57

  @override
  List<double> build(History h) {
    final Vector3 direction = switch (h.command) {
      WalkCommand(:final direction) => direction,
      _ => Vector3.zero(),
    };
    final gyroscope = h.gyroscope * imuGyroscopeScale;
    final pg = h.projectedGravity;
    final jointPosition = (h.jointPosition - standingPose).discardFoot();
    final jointVelocity = h.jointVelocity * jointVelocityScale;
    final action = (h.action - standingPose) / actionScale;
    final obs = [
      gyroscope.x,
      gyroscope.y,
      gyroscope.z,
      pg.x,
      pg.y,
      pg.z,
      direction.x,
      direction.y,
      direction.z,
      ...jointPosition.values,
      ...jointVelocity.values,
      ...action.values,
    ];
    // 防御 NaN/Inf 传入 ONNX（IMU 硬件故障、actionScale 为零等）
    for (int i = 0; i < obs.length; i++) {
      if (!obs[i].isFinite) obs[i] = 0.0;
    }
    return obs;
  }
}

/// Thunder flat 策略的 53 维单帧观测：
/// [gyroscope(3), projectedGravity(3), direction(3),
///  legJointPosition(12), jointVelocity(16), action(16)]
class ThunderFlatObservationBuilder extends StandardObservationBuilder {
  /// Opt in only for policies trained with zero-command wheel action overrides.
  final bool zeroCommandWheelHistory;

  ThunderFlatObservationBuilder({
    required super.standingPose,
    super.actionLowerLimits,
    super.actionUpperLimits,
    super.imuGyroscopeScale,
    super.jointVelocityScale,
    super.actionScale,
    this.zeroCommandWheelHistory = false,
  });

  @override
  int get tensorSize => 3 + 3 + 3 + 12 + 16 + 16; // 53

  @override
  List<double> build(History h) {
    final Vector3 direction = switch (h.command) {
      WalkCommand(:final direction) => direction,
      _ => Vector3.zero(),
    };
    final gyroscope = h.gyroscope * imuGyroscopeScale;
    final pg = h.projectedGravity;
    final legJointPosition = (h.jointPosition - standingPose).values.take(12);
    final jointVelocity = h.jointVelocity * jointVelocityScale;
    final action = (h.action - standingPose) / actionScale;
    final obs = [
      gyroscope.x,
      gyroscope.y,
      gyroscope.z,
      pg.x,
      pg.y,
      pg.z,
      direction.x,
      direction.y,
      direction.z,
      ...legJointPosition,
      ...jointVelocity.values,
      ...action.values,
    ];
    for (int i = 0; i < obs.length; i++) {
      if (!obs[i].isFinite) obs[i] = 0.0;
    }
    return obs;
  }
}

/// Target8500 training clips each raw observation to +/-100 before scaling.
/// Opt-in layout: existing policies retain their original observation contract.
class ThunderFlatClippedObservationBuilder
    extends ThunderFlatObservationBuilder {
  ThunderFlatClippedObservationBuilder({
    required super.standingPose,
    super.actionLowerLimits,
    super.actionUpperLimits,
    super.imuGyroscopeScale,
    super.jointVelocityScale,
    super.actionScale,
  });

  @override
  List<double> build(History h) {
    final direction = switch (h.command) {
      WalkCommand(:final direction) => direction,
      _ => Vector3.zero(),
    };
    final raw = <double>[
      h.gyroscope.x,
      h.gyroscope.y,
      h.gyroscope.z,
      h.projectedGravity.x,
      h.projectedGravity.y,
      h.projectedGravity.z,
      direction.x,
      direction.y,
      direction.z,
      ...(h.jointPosition - standingPose).values.take(12),
      ...h.jointVelocity.values,
      ...((h.action - standingPose) / actionScale).values,
    ];
    final velocityScales =
        (JointsMatrix.fromList(List.filled(16, 1.0)) * jointVelocityScale)
            .values;
    final scales = <double>[
      ...List.filled(3, imuGyroscopeScale),
      ...List.filled(18, 1.0),
      ...velocityScales,
      ...List.filled(16, 1.0),
    ];
    return List.generate(raw.length, (i) {
      if (!raw[i].isFinite || !scales[i].isFinite) {
        throw StateError('Non-finite target8500 observation at index $i');
      }
      return raw[i].clamp(-100.0, 100.0).toDouble() * scales[i];
    });
  }
}

/// CTS V21 shares the per-frame fields but uses a separate dual-input history.
class ThunderCtsObservationBuilder extends ThunderFlatClippedObservationBuilder {
  ThunderCtsObservationBuilder({
    required super.standingPose,
    super.actionLowerLimits,
    super.actionUpperLimits,
    super.imuGyroscopeScale,
    super.jointVelocityScale,
    super.actionScale,
  });
}
