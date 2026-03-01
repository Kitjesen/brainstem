import 'joints_view.dart';

class JointsMatrix with JointsViewMixin<double> {
  @override
  List<double> values;

  // dart format off
  JointsMatrix(double frHip, double frThigh, double frCalf,
              double flHip, double flThigh, double flCalf,
              double rrHip, double rrThigh, double rrCalf,
              double rlHip, double rlThigh, double rlCalf,
              double frFoot, double flFoot, double rrFoot, double rlFoot)
      : values = [
              frHip, frThigh, frCalf,
              flHip, flThigh, flCalf,
              rrHip, rrThigh, rrCalf,
              rlHip, rlThigh, rlCalf,
              frFoot, flFoot, rrFoot, rlFoot
        ];
  // dart format on
  JointsMatrix.fromList(this.values);

  JointsMatrix.zero() : values = List.filled(16, 0.0);

  JointsMatrix operator +(JointsMatrix other) =>
      .fromList(.generate(values.length, (i) => values[i] + other.values[i]));

  JointsMatrix operator -(JointsMatrix other) =>
      .fromList(.generate(values.length, (i) => values[i] - other.values[i]));

  JointsMatrix operator *((double, double, double, double) scales) =>
      scale(scales.$1, scales.$2, scales.$3, scales.$4);
  JointsMatrix operator /((double, double, double, double) scales) =>
      scale(
        scales.$1 != 0 ? 1 / scales.$1 : 0,
        scales.$2 != 0 ? 1 / scales.$2 : 0,
        scales.$3 != 0 ? 1 / scales.$3 : 0,
        scales.$4 != 0 ? 1 / scales.$4 : 0,
      );

  JointsMatrix scale(double hip, double thigh, double calf, double foot) =>
      .fromList([
        frHip * hip,
        frThigh * thigh,
        frCalf * calf,
        flHip * hip,
        flThigh * thigh,
        flCalf * calf,
        rrHip * hip,
        rrThigh * thigh,
        rrCalf * calf,
        rlHip * hip,
        rlThigh * thigh,
        rlCalf * calf,
        frFoot * foot,
        flFoot * foot,
        rrFoot * foot,
        rlFoot * foot,
      ]);

  JointsMatrix discardFoot() {
    return .fromList([
      frHip, frThigh, frCalf,
      flHip, flThigh, flCalf,
      rrHip, rrThigh, rrCalf,
      rlHip, rlThigh, rlCalf,
      0.0, 0.0, 0.0, 0.0, // Discarding foot values
    ]);
  }

  static JointsMatrix lerp(JointsMatrix a, JointsMatrix b, double t) {
    final tc = t.clamp(0.0, 1.0);
    return .fromList(
      .generate(
        a.values.length,
        (i) => a.values[i] + (b.values[i] - a.values[i]) * tc,
      ),
    );
  }

  JointsMatrix clamp([double min = -1.0, double max = 1.0]) =>
      .fromList(values.map((v) => v.clamp(min, max)).toList());

  /// Per-joint-type clamping: each joint type (hip, thigh, calf, foot) has
  /// its own [min, max] range. Layout: [hip, thigh, calf] x 4 legs + foot x 4.
  JointsMatrix clampPerJoint({
    required double hipMin,
    required double hipMax,
    required double thighMin,
    required double thighMax,
    required double calfMin,
    required double calfMax,
    required double footMin,
    required double footMax,
  }) =>
      .fromList([
        frHip.clamp(hipMin, hipMax),
        frThigh.clamp(thighMin, thighMax),
        frCalf.clamp(calfMin, calfMax),
        flHip.clamp(hipMin, hipMax),
        flThigh.clamp(thighMin, thighMax),
        flCalf.clamp(calfMin, calfMax),
        rrHip.clamp(hipMin, hipMax),
        rrThigh.clamp(thighMin, thighMax),
        rrCalf.clamp(calfMin, calfMax),
        rlHip.clamp(hipMin, hipMax),
        rlThigh.clamp(thighMin, thighMax),
        rlCalf.clamp(calfMin, calfMax),
        frFoot.clamp(footMin, footMax),
        flFoot.clamp(footMin, footMax),
        rrFoot.clamp(footMin, footMax),
        rlFoot.clamp(footMin, footMax),
      ]);

  /// Returns true if any value is NaN or infinite.
  bool get hasNonFinite => values.any((v) => v.isNaN || v.isInfinite);

  @override
  String toString() =>
      """
        ${"FR".str}  ${"FL".str}  ${"RR".str}  ${"RL".str}
      ${"_" * 40}
hip   |${frHip.str}, ${flHip.str}, ${rrHip.str}, ${rlHip.str}
thigh |${frThigh.str}, ${flThigh.str}, ${rrThigh.str}, ${rlThigh.str}
calf  |${frCalf.str}, ${flCalf.str}, ${rrCalf.str}, ${rlCalf.str}
foot  |${frFoot.str}, ${flFoot.str}, ${rrFoot.str}, ${rlFoot.str}
""";
}

const _dots = 3;
const _numWidth = _dots * 2 + 1; // 1 for .

extension on double {
  String get str =>
      "${sign < 0 ? '-' : ' '}"
      "${abs().toStringAsFixed(_dots).padLeft(_numWidth, '0')}";
}

extension on String {
  String get str => padLeft(5, ' ').padRight(8, ' ');
}
