import 'dart:async';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

// dart format off
final standingPose = JointsMatrix(
  // 0, 0,  1.2,
  // 0, 0, -1.2,
  // 0, 0,  1.2,
  // 0, 0, -1.2,
  // 0, 0, 0, 0,

  0, -0.64,  1.6,
  0,  0.64, -1.6,
  0,  0.64, -1.6,
  0, -0.64,  1.6,
  0, 0, 0, 0,
  
  // 0, -1.1,  2.2,
  // 0,  1.1, -2.2,
  // 0,  1.1, -2.2,
  // 0, -1.1,  2.2,
  // 0, 0, 0, 0,


  // 0, -0.7,  1.5,
  // 0,  0.7, -1.5,
  // 0,  0.7, -1.5,
  // 0, -0.7,  1.5,
  // 0, 0, 0, 0,
);
// dart format on

class RemoteImu implements ImuService {
  @override
  Vector3 get initialGyroscope => Vector3(0, 0, 0);
  @override
  Vector3 get initialProjectedGravity => Vector3(0, 0, -1);

  @override
  Vector3 gyroscope = Vector3(0, 0, 0);
  Quaternion quaternion = Quaternion.identity();

  @override
  Vector3 get projectedGravity {
    final g = Vector3(0.0, 0.0, -1.0);
    quaternion.rotate(g);
    return g;
  }
}

class RemoteMotor implements JointService {
  @override
  JointsMatrix get initialPosition => .zero();
  @override
  JointsMatrix get initialVelocity => .zero();

  @override
  JointsMatrix position = .zero();
  @override
  JointsMatrix velocity = .zero();
  JointsMatrix torque = .zero();
}

void main() async {
  final imu = RemoteImu();
  final motor = RemoteMotor();
  final timeController = StreamController<void>.broadcast();
  final brain = Brain(
    imu: imu,
    joint: motor,
    clock: timeController,
    standingPose: standingPose,
    sittingPose: .zero(),
    historySize: 1,
  )..loadModel('model/mini_policy6.onnx');
  final m = M(brain)..add(Init());

  await Future.delayed(Duration.zero);

  print(m.state);

  print('start tick');
  final actionSub = brain.nextActionStream.first;
  timeController.add(null);
  final action = await actionSub;
  print('action:\n$action');
  print('end tick');
}
