import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:thunder/src/real_imu.dart';
Future<void> main() async {
  const port='/dev/serial/by-id/usb-Silicon_Labs_CP2102N_USB_to_UART_Bridge_Controller_0e3a84e11af0ef11b457535a6d9880ab-if00-port0';
  final imu=RealImu(port);
  var frames=0;
  Object? error;
  final sub=imu.stateStream.listen((data){frames+=data.length;},onError:(Object e){error=e;});
  var opened=false;
  try {
    opened=imu.open();
    if(opened) await Future<void>.delayed(const Duration(seconds:5));
    final gyro=imu.gyroscope.storage.toList();
    final gravity=imu.projectedGravity.storage.toList();
    final finite=[...gyro,...gravity].every((v)=>v.isFinite);
    final passed=opened && frames>0 && !imu.isStale && finite && error==null;
    print(jsonEncode({'port':port,'opened':opened,'seconds':5,'valid_frames':frames,'mean_hz':frames/5,'gyroscope_rad_s':gyro,'projected_gravity':gravity,'stale':imu.isStale,'finite':finite,'error':error?.toString(),'passed':passed,'motor_objects_created':false,'enable_commands_sent':false,'motion_commands_sent':false}));
    if(!passed)exitCode=1;
  } finally {
    await sub.cancel();
    imu.dispose();
  }
}
