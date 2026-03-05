import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';

void main() async {
  final device = SerialPortController<QPYunZhuoEvent, QPYunZhuoState>(
    '/dev/ttyACM0',
  );

  if (device.open()) {
    print('Serial port opened successfully.');
  } else {
    print('Failed to open serial port.');
    return;
  }

  device.state.listen(print);

  await Future.delayed(const Duration(minutes: 1));
  device.dispose();
}
