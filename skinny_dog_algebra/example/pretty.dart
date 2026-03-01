import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

void main() {
  // dart format off
  final initialStatus = JointsMatrix(
    0.0, 0.7, -1.5,
    0.0, -0.7, 1.5,
    0.0, -0.7, 1.5,
    0.0, 0.7, -1.5,
    0.0, 0.0, 0.0, 0.0
  );
  // dart format on
  print(initialStatus);
  print(3.toStringAsPrecision(3).padLeft(5, '0'));
}
