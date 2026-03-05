import 'dart:math';

import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';
import 'package:pcan/pcan.dart';

final positions = <int, double>{};

void main() async {
  final con = PcanController<RSEvent, RSState>(PcanChannel.usbbus1)..open();
  print('start');
  con.state.listen((state) {
    if (state case RSStateReport(:final canId, :final position)) {
      positions[canId] = position;
      printPositions();
    }
  });
  con.add(.setReporting(3, enable: false));
  // con.add(RSEvent.setReporting(3, enable: true));
  // con.add(RSEvent.setReporting(2, enable: true));
  await Future.delayed(const Duration(minutes: 5));
  con.close();
}

void printPositions() {
  final positionStrings = positions.entries.map(
    (entry) => '${entry.key}:${toDegrees(entry.value).toStringAsFixed(2)}',
  );
  print(positionStrings.join(', '));
}

double toDegrees(double radians) => radians * 180 / pi;
