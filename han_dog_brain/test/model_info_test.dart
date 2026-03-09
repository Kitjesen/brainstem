import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:test/test.dart';

void main() {
  group('inferHistorySizeFromObsDim', () {
    test('returns 1 for single-frame observation', () {
      expect(inferHistorySizeFromObsDim(57, 57), 1);
    });

    test('returns 5 for 285-dim model with 57-dim observation', () {
      expect(inferHistorySizeFromObsDim(285, 57), 5);
    });

    test('returns null when dimensions are not divisible', () {
      expect(inferHistorySizeFromObsDim(286, 57), isNull);
    });

    test('returns null for non-positive values', () {
      expect(inferHistorySizeFromObsDim(0, 57), isNull);
      expect(inferHistorySizeFromObsDim(57, 0), isNull);
    });
  });
}
