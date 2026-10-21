import 'package:han_dog/han_dog.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

void main() {
  test('walking Kp keeps all profile values unchanged', () {
    final baseValues = List<double>.generate(16, (index) => index + 80.0);
    final base = JointsMatrix.fromList(List<double>.from(baseValues));

    final effective = applyHanDogWalkingHipKp(base);

    for (var index = 0; index < 16; index++) {
      expect(
        effective.values[index],
        baseValues[index],
        reason: 'joint index $index',
      );
    }
    expect(base.values, baseValues, reason: 'the configured profile is intact');
  });

  test('walking Kd keeps all profile values unchanged', () {
    final baseValues = List<double>.generate(16, (index) => index + 1.0);
    final base = JointsMatrix.fromList(List<double>.from(baseValues));

    final effective = applyHanDogWalkingHipKdScale(base);

    for (var index = 0; index < 16; index++) {
      expect(
        effective.values[index],
        baseValues[index],
        reason: 'joint index $index',
      );
    }
    expect(base.values, baseValues, reason: 'the configured profile is intact');
  });
}
