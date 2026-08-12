
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root
    ..level = Level.WARNING
    ..onRecord.listen((rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
  final con = PcanController<RSEvent, RSState>(.usbbus1)..open();
  print('SLOW_FULL_ID_SCAN usbbus1/RL start');
  final seen = <int, String>{};
  final sub = con.state.listen((state) {
    final s = state.toString();
    print(s);
    final m = RegExp(r'canId: (\d+).*mcuId: ([0-9]+)').firstMatch(s);
    if (m != null) {
      seen[int.parse(m.group(1)!)] = m.group(2)!;
    }
  });
  for (int i = 0; i < 255; i++) {
    con.add(.getDeviceId(i));
    await Future.delayed(const Duration(milliseconds: 20));
  }
  await Future.delayed(const Duration(seconds: 2));
  print('SUMMARY_BEGIN');
  final ids = seen.keys.toList()..sort();
  if (ids.isEmpty) {
    print('NO_DEVICE_ID_RESPONSE');
  } else {
    for (final id in ids) {
      print('FOUND canId=$id mcuId=${seen[id]}');
    }
  }
  print('SUMMARY_END');
  await sub.cancel();
  con.dispose();
}
