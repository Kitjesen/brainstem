import 'dart:async';

import 'package:serial_port/serial_port.dart';

void main() async {
  final serialPort = SerialPort();
  serialPort.init('/dev/ttyUSB0');

  if (serialPort.open()) {
    print('Serial port opened successfully: ${serialPort.portName}');
  } else {
    print(
      'Failed to open ${serialPort.portName}: ${serialPort.lastErrorCode}(${serialPort.lastErrorMessage})',
    );
    return;
  }

  serialPort.onData.listen(print);

  await Future.delayed(const Duration(seconds: 1));
  serialPort.dispose();
}
