import 'package:robo_device/src/serial_port/controller.dart';
import 'package:logging/logging.dart';
import 'package:robo_device_proto/device_proto.dart';

void main() async {
  Logger.root
    ..level = .ALL
    ..onRecord.listen((record) {
      print('[${record.level.name}] ${record.time}: ${record.message}');
    });

  final device = SerialPortController<Never, YunZhuoState>('/dev/ttyUSB0');

  if (!device.open()) {
    device.dispose();
    return;
  }

  device.state.listen(print);

  await Future.delayed(const .new(seconds: 10));
  device.dispose();
}
