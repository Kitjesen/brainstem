
import 'dart:async';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

void main() async {
  const oldId = 127;
  const newId = 2;
  final con = PcanController<RSEvent, RSState>(.usbbus1)..open();
  final seen = <int, String>{};
  final sub = con.state.listen((state) {
    if (state is RSStateDeviceId) {
      seen[state.canId] = state.mcuId.toString();
      print('deviceId canId=${state.canId} mcuId=${state.mcuId}');
    } else if (state is RSStateReport) {
      print('report canId=${state.canId} status=${state.status} pos=${state.position.toStringAsFixed(4)} temp=${state.temperature} errors=${state.errors}');
    } else {
      print(state);
    }
  });

  print('open usbbus1, verify oldId=$oldId and newId=$newId before write');
  con.add(RSEvent.getDeviceId(1));
  con.add(RSEvent.getDeviceId(oldId));
  con.add(RSEvent.getDeviceId(newId));
  await Future.delayed(const Duration(milliseconds: 800));

  if (!seen.containsKey(oldId)) {
    print('ABORT: oldId=$oldId did not respond; not writing id. seen=$seen');
    await sub.cancel();
    con.close();
    return;
  }
  if (seen.containsKey(newId)) {
    print('ABORT: newId=$newId already responds; refusing to create duplicate id. seen=$seen');
    await sub.cancel();
    con.close();
    return;
  }

  print('WRITE: setId oldId=$oldId -> newId=$newId');
  con.add(RSEvent.setId(oldId, newId: newId));
  await Future.delayed(const Duration(milliseconds: 1200));

  seen.clear();
  print('verify after write');
  con.add(RSEvent.getDeviceId(1));
  con.add(RSEvent.getDeviceId(oldId));
  con.add(RSEvent.getDeviceId(newId));
  con.add(RSEvent.setReporting(newId, enable: true));
  await Future.delayed(const Duration(milliseconds: 1500));

  con.add(RSEvent.setReporting(newId, enable: false));
  await Future.delayed(const Duration(milliseconds: 200));
  await sub.cancel();
  con.close();
}
