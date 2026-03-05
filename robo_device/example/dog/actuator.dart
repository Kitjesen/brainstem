import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';
import 'package:pcan/pcan.dart';

void main() async {
  final p1 = PcanController<RSEvent, RSState>(.usbbus1)..open();
  final p2 = PcanController<RSEvent, RSState>(.usbbus2)..open();
  final p3 = PcanController<RSEvent, RSState>(.usbbus3)..open();
  final p4 = PcanController<RSEvent, RSState>(.usbbus4)..open();
  print('start');
  p1.state.listen((s) => print('p1: $s'));
  p2.state.listen((s) => print('p2: $s'));
  p3.state.listen((s) => print('p3: $s'));
  p4.state.listen((s) => print('p4: $s'));
  for (int i = 0; i < 255; i++) {
    p1.add(RSEvent.getDeviceId(i));
    p2.add(RSEvent.getDeviceId(i));
    p3.add(RSEvent.getDeviceId(i));
    p4.add(RSEvent.getDeviceId(i));
  }
  await Future.delayed(const Duration(seconds: 1));
  p1.close();
  p2.close();
  p3.close();
  p4.close();
}
