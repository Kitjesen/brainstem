import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen((rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
  final con = PcanController<RSEvent, RSState>(.usbbus1)..open();
  print('start');
  con.state.listen((state) {
    print(state);
  });
  for (int i = 0; i < 255; i++) {
    con.add(.getDeviceId(i));
  }
  await Future.delayed(const Duration(seconds: 1));
  con.dispose();
}
