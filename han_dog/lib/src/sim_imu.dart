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
