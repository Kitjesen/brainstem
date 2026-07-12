import 'dart:async';
import 'dart:io';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

void main() async {
  const oldId = 3;
  const newId = 1;
  const expectedMcu = '1101474833161124806';

  final con = PcanController<RSEvent, RSState>(.usbbus1);
  if (!con.open()) {
    print('ABORT: failed to open usbbus1/RL');
    exitCode = 1;
    return;
  }

  final seen = <int, String>{};
  final sub = con.state.listen((state) {
    if (state is RSStateDeviceId) {
      seen[state.canId] = state.mcuId.toString();
      print('deviceId canId=${state.canId} mcuId=${state.mcuId}');
    } else if (state is RSStateReport) {
      print(
        'report canId=${state.canId} status=${state.status} '
        'pos=${state.position.toStringAsFixed(4)} '
        'vel=${state.velocity.toStringAsFixed(4)} '
        'torque=${state.torque.toStringAsFixed(4)} '
        'temp=${state.temperature} errors=${state.errors}',
      );
    } else {
      print(state);
    }
  });

  Future<void> pingIds(Iterable<int> ids) async {
    for (final id in ids) {
      con.add(RSEvent.getDeviceId(id));
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

  print('VERIFY before write: RL/usbbus1 oldId=$oldId -> newId=$newId');
  await pingIds(const [newId, 2, oldId, 4]);

  if (seen[newId] != null) {
    print('ABORT: newId=$newId already exists, refusing duplicate ID. seen=$seen');
    await sub.cancel();
    con.close();
    exitCode = 2;
    return;
  }
  if (seen[oldId] != expectedMcu) {
    print('ABORT: oldId=$oldId MCU mismatch. expected=$expectedMcu seen=$seen');
    await sub.cancel();
    con.close();
    exitCode = 3;
    return;
  }

  print('WRITE: setId oldId=$oldId mcu=$expectedMcu -> newId=$newId');
  con.add(RSEvent.setId(oldId, newId: newId));
  await Future<void>.delayed(const Duration(milliseconds: 1500));

  seen.clear();
  print('VERIFY after write: expect only newId=$newId');
  await pingIds(const [newId, 2, oldId, 4]);

  if (seen[newId] == expectedMcu && seen[oldId] == null) {
    print('OK: MCU $expectedMcu is now canId=$newId on RL/usbbus1');
    con.add(RSEvent.setReporting(newId, enable: true));
    await Future<void>.delayed(const Duration(seconds: 1));
    con.add(RSEvent.setReporting(newId, enable: false));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  } else {
    print('FAIL: unexpected result after setId. seen=$seen');
    exitCode = 4;
  }

  await sub.cancel();
  con.close();
}
