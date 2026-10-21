import 'package:han_dog/src/real_control_dog.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('shapeSignedCommand', () {
    test('returns zero throughout the deadzone', () {
      expect(
        shapeSignedCommand(
          0.10,
          deadzone: 0.10,
          minCommand: 0.0,
          maxCommand: 0.4,
        ),
        0.0,
      );
    });

    test('allows proportional low-speed lateral commands', () {
      final result = shapeSignedCommand(
        0.325,
        deadzone: 0.10,
        minCommand: 0.0,
        maxCommand: 0.4,
      );
      expect(result, closeTo(0.10, 1e-9));
    });

    test('maps the active stick range continuously from 0.3 to 1.0', () {
      expect(
        shapeSignedCommand(
          0.100001,
          deadzone: 0.10,
          minCommand: 0.3,
          maxCommand: 1.0,
        ),
        closeTo(0.30000078, 1e-6),
      );
      expect(
        shapeSignedCommand(
          0.55,
          deadzone: 0.10,
          minCommand: 0.3,
          maxCommand: 1.0,
        ),
        closeTo(0.65, 1e-9),
      );
      expect(
        shapeSignedCommand(
          1.0,
          deadzone: 0.10,
          minCommand: 0.3,
          maxCommand: 1.0,
        ),
        1.0,
      );
    });

    test('saturates YUNZHUO inputs above one to the profile maximum', () {
      expect(
        shapeSignedCommand(
          1.5,
          deadzone: 0.10,
          minCommand: 0.0,
          maxCommand: 0.4,
        ),
        0.4,
      );
      expect(
        shapeSignedCommand(
          -1.5,
          deadzone: 0.10,
          minCommand: 0.0,
          maxCommand: 0.25,
        ),
        -0.25,
      );
    });
  });

  group('DogCommandRateLimiter', () {
    final epoch = DateTime.utc(2026);
    DateTime at(int milliseconds) =>
        epoch.add(Duration(milliseconds: milliseconds));

    test('limits each axis with its configured acceleration', () {
      final limiter = DogCommandRateLimiter();
      expect(limiter.limit(Vector3.all(1), at(0)), Vector3.zero());

      final next = limiter.limit(Vector3.all(1), at(10));
      expect(next.x, closeTo(0.020, 1e-7));
      expect(next.y, closeTo(0.015, 1e-7));
      expect(next.z, closeTo(0.012, 1e-7));
    });

    test('a direction reversal decelerates to zero before crossing it', () {
      final limiter = DogCommandRateLimiter();
      limiter.limit(Vector3.all(1), at(0));
      for (var milliseconds = 10; milliseconds <= 100; milliseconds += 10) {
        limiter.limit(Vector3.all(1), at(milliseconds));
      }

      final reversing = limiter.limit(Vector3.all(-1), at(110));
      expect(reversing.x, closeTo(0.17, 1e-7));
      expect(reversing.y, closeTo(0.125, 1e-7));
      expect(reversing.z, isNonNegative);
    });

    test('caps catch-up after a delayed control iteration', () {
      final limiter = DogCommandRateLimiter();
      limiter.limit(Vector3.all(1), at(0));
      final delayed = limiter.limit(Vector3.all(1), at(1000));

      expect(delayed.x, closeTo(0.060, 1e-7));
      expect(delayed.y, closeTo(0.045, 1e-7));
      expect(delayed.z, closeTo(0.036, 1e-7));
    });

    test('reset clears command and timing state', () {
      final limiter = DogCommandRateLimiter();
      limiter.limit(Vector3.all(1), at(0));
      limiter.limit(Vector3.all(1), at(10));
      limiter.reset();

      expect(limiter.value, Vector3.zero());
      expect(limiter.limit(Vector3.all(1), at(20)), Vector3.zero());
    });
  });
}
