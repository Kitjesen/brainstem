import 'package:pcan/pcan.dart';

void main() {
  print(Pcan.apiVersion);
  final pcan = Pcan(.usbbus1);
  print(pcan.condition);
  pcan.open(.baud500K);
  // print(pcan.firmwareVersion);
  // print('Device ID: ${pcan.deviceId}');
  // pcan.deviceId = 2;
  // print(pcan.guid);
  // pcan.blink = true;

  // print(pcan.blink);
  // // pcan.blink = false;
  // print(pcan.blink);
  // pcan.deviceId = 1234;
  // print('Device ID: ${pcan.deviceId}');
}
