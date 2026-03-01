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
