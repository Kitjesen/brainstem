/// **已废弃**：请使用 `server/sim_sensor.dart` 中的 [SimSensorService]。
///
/// SimSensorService 同时实现了 ImuService、JointService 和 SimStateInjector，
/// 是仿真模式的标准实现。本文件仅供参考，后续版本将移除。
library;

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:vector_math/vector_math.dart';

class SimImu implements ImuService {
  @override
  Vector3 get initialGyroscope => .zero();
  @override
  Vector3 get initialProjectedGravity => Vector3(0, 0, -1);

  @override
  Vector3 gyroscope = Vector3(0, 0, 0);

  var quaternion = Quaternion.identity();

  @override
  Vector3 get projectedGravity => quaternion.rotate(Vector3(0, 0, -1));
}
