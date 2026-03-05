import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root
    ..level = .ALL
    ..onRecord.listen((record) {
      print('[${record.level.name}] ${record.time}: ${record.message}');
    });

  final device = SerialPortController<Hi91Event, Hi91State>('/dev/ttyUSB0');

  if (!device.open()) {
    device.dispose();
    return;
  }

  device.state.listen(print);

  await Future.delayed(const .new(seconds: 10));
  device.dispose();
}
