import 'dart:math';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

void main() async {
  final con = PcanController<RSEvent, RSState>(.usbbus1)..open();
  print('start');
  con.state.listen((state) {
    print(state);
  });
  con.add(.disable(5));
  // Han Dog CAN ID 1 is the RS04 hip motor. Motor IDs and models are declared
  // centrally in robo_device_proto's hanDogMotorLayout.
  con.add(.control(1, position: pi / 2, kd: 1, kp: 50));
  await Future.delayed(const Duration(seconds: 1));
  con.close();
}
