import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';

void main() async {
  final con = PcanController<DMG6620Event, DMG6620State>(.usbbus1)..open();
  print('start');
  con.state.listen((state) {
    print(state);
  });
  con.add(.disable(1));
  await Future.delayed(const .new(seconds: 1));
  con.close();
}
