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
}

/// 标准 57 维观测构建器：
/// [gyroscope(3), projectedGravity(3), direction(3),
///  jointPosition(16), jointVelocity(16), action(16)]
class StandardObservationBuilder implements ObservationBuilder {
  @override
  final (double, double, double, double) actionScale;

  @override
  final JointsMatrix standingPose;

  final double imuGyroscopeScale;
  final (double, double, double, double) jointVelocityScale;

  StandardObservationBuilder({
    required this.standingPose,
    this.imuGyroscopeScale = 0.25,
    this.jointVelocityScale = (0.05, 0.05, 0.05, 0.05),
    this.actionScale = (0.125, 0.25, 0.25, 5.0),
  });

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
    return [
      gyroscope.x, gyroscope.y, gyroscope.z,
      pg.x, pg.y, pg.z,
      direction.x, direction.y, direction.z,
      ...jointPosition.values,
      ...jointVelocity.values,
      ...action.values,
    ];
  }
}
