import 'dart:async';

import 'package:serial_port/serial_port.dart';

void main() async {
  final serialPort = SerialPort();
  serialPort.init('/dev/ttyACM0');

  if (serialPort.open()) {
    print('Serial port opened successfully: ${serialPort.portName}');
  } else {
    print(
      'Failed to open ${serialPort.portName}: ${serialPort.lastErrorCode}(${serialPort.lastErrorMessage})',
    );
    serialPort.dispose();
    return;
  }

  int frequency = 0;
  int counts = 0;

  Timer.periodic(const Duration(seconds: 1), (timer) {
    frequency = counts;
    counts = 0;
  });

  serialPort.onData.listen((data) {
    print('$frequency hz: $data');
    counts++;
  });
}
