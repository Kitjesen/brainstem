import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';
import 'package:logging/logging.dart';
import 'package:pcan/pcan.dart';

void main() async {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen((record) {
      print('[${record.level.name}] ${record.time}: ${record.message}');
    });

  final p1 = PcanController<RSEvent, RSState>(.usbbus1)..open();
  final p2 = PcanController<RSEvent, RSState>(.usbbus2)..open();
  final p3 = PcanController<RSEvent, RSState>(.usbbus3)..open();
  final p4 = PcanController<RSEvent, RSState>(.usbbus4)..open();
  print('start');
  p1.state.listen((s) => print('p1: $s'));
  p2.state.listen((s) => print('p2: $s'));
  p3.state.listen((s) => print('p3: $s'));
  p4.state.listen((s) => print('p4: $s'));
  for (int i = 1; i < 4; i++) {
    p1.add(.setReporting(i, enable: true));
    p2.add(.setReporting(i, enable: true));
    p3.add(.setReporting(i, enable: true));
    p4.add(.setReporting(i, enable: true));
  }
  await Future.delayed(const Duration(seconds: 1));
  for (int i = 1; i < 4; i++) {
    p1.add(.setReporting(i, enable: false));
    p2.add(.setReporting(i, enable: false));
    p3.add(.setReporting(i, enable: false));
    p4.add(.setReporting(i, enable: false));
  }

  p1.dispose();
  p2.dispose();
  p3.dispose();
  p4.dispose();
}
