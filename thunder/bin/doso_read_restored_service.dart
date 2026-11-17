import 'dart:convert';
import 'package:grpc/grpc.dart' as grpc;
import 'package:brainstem_api/brainstem_api.dart' as msg;

Future<void> main() async {
  final channel = grpc.ClientChannel('127.0.0.1', port: 13145,
      options: const grpc.ChannelOptions(credentials: grpc.ChannelCredentials.insecure()));
  final client = msg.RobotControlClient(channel);
  try {
    final state = await client.getCmsState(msg.Empty(),
        options: grpc.CallOptions(timeout: const Duration(seconds: 4)));
    print('READ_ONLY_CMS ${jsonEncode(state.toProto3Json())}');
    final profile = await client.getProfile(msg.Empty(),
        options: grpc.CallOptions(timeout: const Duration(seconds: 4)));
    print('READ_ONLY_PROFILE ${jsonEncode(profile.toProto3Json())}');
    final joint = await client.listenJoint(msg.Empty(),
        options: grpc.CallOptions(timeout: const Duration(seconds: 4))).first;
    print('READ_ONLY_JOINT ${jsonEncode(joint.toProto3Json())}');
    final motors = await client.getMotorStatus(msg.Empty(),
        options: grpc.CallOptions(timeout: const Duration(seconds: 4)));
    print('READ_ONLY_MOTORS ${jsonEncode(motors.toProto3Json())}');
    if (motors.motors.length != 16 || motors.motors.any((motor) => !motor.online || motor.statusCode == 2)) {
      throw StateError('Expected 16 online motors without enabled status');
    }
    final imu = await client.listenImu(msg.Empty(),
        options: grpc.CallOptions(timeout: const Duration(seconds: 4))).first;
    print('READ_ONLY_IMU ${jsonEncode(imu.toProto3Json())}');
  } finally {
    await channel.shutdown();
  }
}

