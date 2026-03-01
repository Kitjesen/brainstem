import 'package:skinny_dog_algebra/src/joints_matrix.dart';
import 'package:test/test.dart';

void main() {
  test('to string', () {
    expect(
      // dart format off
      JointsMatrix(
        0.0, 0.7, -1.5,
        0.0, -0.7, 1.5,
        0.0, -0.7, 1.5,
        0.0, 0.7, -1.5,
        0.0, 0.0, 0.0, 0.0
      ).toString(),
      // dart format on
      """
           FR        FL        RR        RL   
      ________________________________________
hip   | 000.000,  000.000,  000.000,  000.000
thigh | 000.700, -000.700, -000.700,  000.700
calf  |-001.500,  001.500,  001.500, -001.500
foot  | 000.000,  000.000,  000.000,  000.000
""",
    );
  });

  group('clampPerJoint', () {
    test('clamps values exceeding range', () {
      // dart format off
      final m = JointsMatrix(
        1.0,  3.0,  5.0,   // FR: hip out, thigh out, calf out
       -1.0, -3.0, -5.0,   // FL: all out (negative)
        0.2,  0.5,  1.0,   // RR: all within range
       -0.2, -0.5, -1.0,   // RL: all within range
        2.0, -2.0, 0.3, -0.3, // foot: some out
      );
      // dart format on
      final clamped = m.clampPerJoint(
        hipMin: -0.5, hipMax: 0.5,
        thighMin: -1.5, thighMax: 1.5,
        calfMin: -2.5, calfMax: 2.5,
        footMin: -0.5, footMax: 0.5,
      );
      // FR: hip 1.0 -> 0.5, thigh 3.0 -> 1.5, calf 5.0 -> 2.5
      expect(clamped.frHip, 0.5);
      expect(clamped.frThigh, 1.5);
      expect(clamped.frCalf, 2.5);
      // FL: hip -1.0 -> -0.5, thigh -3.0 -> -1.5, calf -5.0 -> -2.5
      expect(clamped.flHip, -0.5);
      expect(clamped.flThigh, -1.5);
      expect(clamped.flCalf, -2.5);
      // RR: all within range, unchanged
      expect(clamped.rrHip, 0.2);
      expect(clamped.rrThigh, 0.5);
      expect(clamped.rrCalf, 1.0);
      // RL: all within range, unchanged
      expect(clamped.rlHip, -0.2);
      expect(clamped.rlThigh, -0.5);
      expect(clamped.rlCalf, -1.0);
      // foot: 2.0 -> 0.5, -2.0 -> -0.5, 0.3 unchanged, -0.3 unchanged
      expect(clamped.frFoot, 0.5);
      expect(clamped.flFoot, -0.5);
      expect(clamped.rrFoot, 0.3);
      expect(clamped.rlFoot, -0.3);
    });

    test('values within range are unchanged', () {
      // dart format off
      final m = JointsMatrix(
        0.1, 0.5, 1.0,
       -0.1, -0.5, -1.0,
        0.0, 1.2, -2.0,
        0.3, -1.0, 2.0,
        0.0, 0.1, -0.1, 0.4,
      );
      // dart format on
      final clamped = m.clampPerJoint(
        hipMin: -0.5, hipMax: 0.5,
        thighMin: -1.5, thighMax: 1.5,
        calfMin: -2.5, calfMax: 2.5,
        footMin: -0.5, footMax: 0.5,
      );
      for (int i = 0; i < 16; i++) {
        expect(clamped.values[i], m.values[i],
            reason: 'index $i should be unchanged');
      }
    });
  });

  group('hasNonFinite', () {
    test('returns false for normal values', () {
      expect(JointsMatrix.zero().hasNonFinite, isFalse);
      expect(
        JointsMatrix.fromList(List.filled(16, 1.5)).hasNonFinite,
        isFalse,
      );
    });

    test('returns true when NaN present', () {
      final values = List.filled(16, 0.0);
      values[7] = double.nan;
      expect(JointsMatrix.fromList(values).hasNonFinite, isTrue);
    });

    test('returns true when positive Infinity present', () {
      final values = List.filled(16, 0.0);
      values[3] = double.infinity;
      expect(JointsMatrix.fromList(values).hasNonFinite, isTrue);
    });

    test('returns true when negative Infinity present', () {
      final values = List.filled(16, 0.0);
      values[15] = double.negativeInfinity;
      expect(JointsMatrix.fromList(values).hasNonFinite, isTrue);
    });
  });
}
