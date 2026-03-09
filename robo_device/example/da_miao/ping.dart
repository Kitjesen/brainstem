import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

void main() async {
  final con = PcanController<DMG6620Event, DMG6620State>(.usbbus1)..open();
  print('start');
  con.state.listen((state) {
    print(state);
  });
  for (int i = 0; i < 255; i++) {
    con.add(.disable(i));
  }
  await Future.delayed(const .new(seconds: 1));
  con.close();
}
