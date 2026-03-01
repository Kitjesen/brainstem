import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

void main() {
  // dart format off
  final s1 = JointsMatrix(
    0.0, 0.7, -1.5,
    0.0, -0.7, 1.5,
    0.0, -0.7, 1.5,
    0.0, 0.7, -1.5,
    0.0, 0.0, 0.0, 0.0
  );
  // dart format on
  final s0 = JointsMatrix.zero();
  for (double t = 0; t <= 1; t += 0.1) {
    final status = JointsMatrix.lerp(s0, s1, t);
    print('t: $t, status: \n${status.toString()}');
  }
}
