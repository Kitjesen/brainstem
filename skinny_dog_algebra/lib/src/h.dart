import 'package:equatable/equatable.dart';
import 'package:vector_math/vector_math.dart';

import 'joints_matrix.dart';

class ToleranceH {
  /// - h: 代表普朗克常数，象征精度级别
  static double h = 1e-9;

  static bool areEqual(double a, double b) => (a - b).abs() < h;
}

class DoubleH {
  final double value;
  const DoubleH(this.value);

  @override
  bool operator ==(Object other) => switch (other) {
    DoubleH o => ToleranceH.areEqual(value, o.value),
    double o => ToleranceH.areEqual(value, o),
    _ => false,
  };

  @override
  String toString() => value.toString();

  @override
  int get hashCode {
    if (value.isNaN || value.isInfinite) return value.hashCode;
    return (value / ToleranceH.h).round().hashCode;
  }
}

extension DoubleHExt on double {
  DoubleH get h => DoubleH(this);
}

class Vector3H extends Equatable {
  final DoubleH x, y, z;
  const Vector3H(this.x, this.y, this.z);

  @override
  List<Object?> get props => [x, y, z];
}

extension Vector3HExt on Vector3 {
  Vector3H get h => Vector3H(x.h, y.h, z.h);
}

class JointsMatrixH extends Equatable {
  final List<DoubleH> values;
  const JointsMatrixH(this.values);

  @override
  List<Object?> get props => values;
}

extension JointsMatrixHExt on JointsMatrix {
  JointsMatrixH get h => JointsMatrixH(values.map((v) => v.h).toList());
}
