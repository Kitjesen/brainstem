import 'dart:io';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

import '../real_joint.dart';

// Verified S100 USB topology on 2026-10-26; logical leg order stays FR/FL/RR/RL.
const rdkS100PcanRoutes = {
  'FR': (channel: PcanChannel.usbbus1, interface: 'can0', usb: '1-1.1'),
  'FL': (channel: PcanChannel.usbbus3, interface: 'can2', usb: '1-1.2'),
  'RR': (channel: PcanChannel.usbbus2, interface: 'can1', usb: '1-2.1'),
  'RL': (channel: PcanChannel.usbbus4, interface: 'can3', usb: '1-1.3'),
};

void validateRdkS100JointTopology({
  required Map<String, String> environment,
  String Function(String)? resolvePath,
}) {
  if (resolvePath == null && !Platform.isLinux) {
    throw UnsupportedError('rdk-s100-pcan requires Linux');
  }
  final resolve =
      resolvePath ?? (path) => File(path).resolveSymbolicLinksSync();
  for (final entry in rdkS100PcanRoutes.entries) {
    final route = entry.value;
    final path = resolve('/sys/class/net/${route.interface}/device');
    if (!path.split('/').contains(route.usb)) {
      throw StateError(
        '${entry.key}/${route.interface}: expected USB ${route.usb}, got $path',
      );
    }
  }
  final imu = environment['THUNDER_IMU_PORT'];
  if (imu == null || imu.trim().isEmpty) {
    throw StateError('Set THUNDER_IMU_PORT explicitly for rdk-s100-pcan');
  }
  resolve(imu);
}

/// Construct only; opening this joint still performs the existing startup stop.
RealJoint createHardwareJoint({
  Map<String, String>? environment,
  String Function(String)? resolvePath,
}) {
  final env = environment ?? Platform.environment;
  switch (env['THUNDER_JOINT_TRANSPORT'] ?? 'pcan') {
    case 'pcan':
      return RealJoint(
        fr: PcanChannel.usbbus4,
        fl: PcanChannel.usbbus3,
        rr: PcanChannel.usbbus2,
        rl: PcanChannel.usbbus1,
      );
    case 'rdk-s100-mixed':
      throw StateError(
        'RR AT was replaced; use rdk-s100-pcan with the new USB mapping',
      );
    case 'rdk-s100-pcan':
      validateRdkS100JointTopology(environment: env, resolvePath: resolvePath);
      return RealJoint.withControllers([
        for (final leg in ['FR', 'FL', 'RR', 'RL'])
          PcanController<RSEvent, RSState>.withPcan(
            Pcan.socketCan(rdkS100PcanRoutes[leg]!.channel),
          ),
      ]);
    default:
      throw ArgumentError(
        'Unknown THUNDER_JOINT_TRANSPORT: ${env['THUNDER_JOINT_TRANSPORT']}',
      );
  }
}
