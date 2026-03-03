/// **已废弃**：请使用 `server/sim_sensor.dart` 中的 [SimSensorService]。
///
/// SimSensorService 同时实现了 ImuService、JointService 和 SimStateInjector，
/// 是仿真模式的标准实现。本文件仅供参考，后续版本将移除。
library;

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

class SimJoint implements JointService {
  @override
  JointsMatrix get initialPosition => .zero();
  @override
  JointsMatrix get initialVelocity => .zero();

  @override
  JointsMatrix position = .zero();
  @override
  JointsMatrix velocity = .zero();

  var kp = JointsMatrix.zero();
  var kd = JointsMatrix.zero();
}
