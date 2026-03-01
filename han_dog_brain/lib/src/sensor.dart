import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

abstract interface class ImuService {
  Vector3 get gyroscope;
  Vector3 get projectedGravity;

  Vector3 get initialGyroscope;
  Vector3 get initialProjectedGravity;
}

abstract interface class JointService {
  JointsMatrix get position;
  JointsMatrix get velocity;

  JointsMatrix get initialPosition;
  JointsMatrix get initialVelocity;
}

abstract interface class MotorService {
  Future<void> enable();
  Future<void> disable();
  void sendAction(JointsMatrix action);
}

/// 仿真传感器注入接口。
/// 真实硬件不需要实现此接口；仿真实现（如 SimSensorService）实现它。
abstract interface class SimStateInjector {
  /// 最近一次注入的四元数，供 listenImu 读取。
  Quaternion get quaternion;

  void injectSim({
    required Vector3 gyroscope,
    required Quaternion quaternion,
    required JointsMatrix position,
    required JointsMatrix velocity,
    JointsMatrix? torque,
  });
}
