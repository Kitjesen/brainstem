import 'dart:convert';
import 'dart:io';

import 'package:thunder/src/app/joint_transport.dart';

void main() {
  if (Platform.environment['THUNDER_JOINT_TRANSPORT'] != 'rdk-s100-pcan') {
    throw StateError(
      'This check requires the prepared rdk-s100-pcan environment',
    );
  }
  // Never call open(): RealJoint.open() sends startup motor commands.
  final joint = createHardwareJoint();
  try {
    print(
      jsonEncode({
        'transport': 'rdk-s100-pcan',
        'ports_opened': false,
        'motor_commands_sent': false,
        'imu': File(
          Platform.environment['THUNDER_IMU_PORT']!,
        ).resolveSymbolicLinksSync(),
        'routes': [
          for (final entry in rdkS100PcanRoutes.entries)
            {
              'leg': entry.key,
              'interface': entry.value.interface,
              'channel': entry.value.channel.name,
              'usb': entry.value.usb,
            },
        ],
        'write_intervals_ms': joint.pcans
            .map((p) => p.writeInterval.inMilliseconds)
            .toList(),
      }),
    );
  } finally {
    joint.dispose();
  }
}
