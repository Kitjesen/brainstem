import 'dart:math';

import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';
import 'package:pcan/pcan.dart';

void main() async {
  final con = PcanController<RSEvent, RSState>(.usbbus1)..open();
  print('start');
  con.state.listen((state) {
    print(state);
  });
  con.add(.disable(5));
  con.add(.control(5, position: pi / 2, kd: 1, kp: 50));
  await Future.delayed(const Duration(seconds: 1));
  con.close();
}
