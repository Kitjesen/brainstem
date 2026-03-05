import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';
import 'package:pcan/pcan.dart';

void main() async {
  final con = PcanController<RSEvent, RSState>(.usbbus1)..open();
  print('start');
  con.state.listen((state) {
    print(state);
  });
  con.add(RSEvent.setId(21, newId: 1));
  await Future.delayed(const Duration(seconds: 1));
  con.close();
}
