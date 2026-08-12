import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart';
import 'package:grpc/grpc.dart';

const _names = [
  'FR Hip',
  'FR Thigh',
  'FR Calf',
  'FL Hip',
  'FL Thigh',
  'FL Calf',
  'RR Hip',
  'RR Thigh',
  'RR Calf',
  'RL Hip',
  'RL Thigh',
  'RL Calf',
  'FR Foot',
  'FL Foot',
  'RR Foot',
  'RL Foot',
];

void main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : 'localhost';
  final channel = ClientChannel(
    host,
    port: 13145,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  final client = RobotControlClient(channel);

  try {
    final cms = await client.getCmsState(Empty());
    print('cms kind=${cms.kind.name} transition=${cms.transition.name}');

    final status = await client.getMotorStatus(Empty());
    final voltages = await client.getVoltage(Empty());
    var online = 0;
    var errorFree = 0;

    for (final m in status.motors) {
      if (m.online) online++;
      if (m.errors.isEmpty) errorFree++;
      final name = m.id < _names.length ? _names[m.id] : 'Joint ${m.id}';
      final voltage = m.id < voltages.values.length ? voltages.values[m.id] : 0.0;
      print(
        '${m.id.toString().padLeft(2)} ${name.padRight(8)} '
        'online=${m.online.toString().padRight(5)} '
        'status=${m.statusCode.toString().padLeft(2)} '
        'err=${m.errors} '
        'pos=${m.position.toStringAsFixed(4).padLeft(8)} '
        'vel=${m.velocity.toStringAsFixed(4).padLeft(8)} '
        'tau=${m.torque.toStringAsFixed(4).padLeft(8)} '
        'temp=${m.temperature.toStringAsFixed(1).padLeft(4)} '
        'vbus=${voltage.toStringAsFixed(2)}',
      );
    }

    print('summary online=$online/${status.motors.length} errorFree=$errorFree/${status.motors.length}');
    exitCode = online == status.motors.length && errorFree == status.motors.length ? 0 : 2;
  } finally {
    await channel.shutdown();
  }
}
