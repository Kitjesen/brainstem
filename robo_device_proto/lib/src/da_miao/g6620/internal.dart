import 'dart:typed_data';

import 'package:robo_device_proto/src/can_frame.dart';

const double positionMax = 12.5;
const double velocityMax = 45.0;
const double torqueMax = 10.0;
const double kpMax = 500.0;
const double kdMax = 5.0;

CanFrame canFrame({required int id, required Uint8List data}) =>
    .new(id: id, data: data, type: CanType.standard);

int floatToUint(double x, double xMin, double xMax, int bits) {
  double span = xMax - xMin;
  double offset = xMin;
  return ((x - offset) * (((1 << bits) - 1)) / span).toInt();
}

double uintToFloat(int n, double nMin, double nMax, int bits) {
  double span = nMax - nMin;
  double offset = nMin;
  return (n) * span / (((1 << bits) - 1)) + offset;
}
