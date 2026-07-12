library;

import 'package:grpc/grpc.dart';
import 'package:brainstem_api/brainstem_api.dart' hide Duration;

const _names = ['FR', 'FL', 'RR', 'RL'];

void main(List<String> args) async {
  final host = _arg(args, '--host', 'localhost');
  final port = int.parse(_arg(args, '--port', '13145'));
  final seconds = int.parse(_arg(args, '--seconds', '12'));

  final channel = ClientChannel(
    host,
    port: port,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  final client = RobotControlClient(channel);
  final until = DateTime.now().add(Duration(seconds: seconds));
  var lastPrint = DateTime.fromMillisecondsSinceEpoch(0);

  print('Read-only wheel response watcher: $host:$port ${seconds}s');
  print('Hold one command at a time: left/right strafe, then yaw. Ctrl+C to stop.');
  print('cmd=(vx,vy,wz)  target wheel=[FR,FL,RR,RL]  actual wheel vel=[FR,FL,RR,RL]');

  try {
    await for (final h in client.listenHistory(Empty())) {
      if (DateTime.now().isAfter(until)) break;
      if (DateTime.now().difference(lastPrint).inMilliseconds < 200) continue;
      lastPrint = DateTime.now();

      final cmd = h.command.hasWalk() ? h.command.walk : Vector3();
      final target = _wheel(h.nextAction.values);
      final vel = _wheel(h.jointVelocity.values);
      print(
        'cmd=(${_f(cmd.x)}, ${_f(cmd.y)}, ${_f(cmd.z)})  '
        'target=${_fmt(target)}  vel=${_fmt(vel)}',
      );
    }
  } finally {
    await channel.shutdown();
  }
}

List<double> _wheel(List<double> values) =>
    [for (final i in [12, 13, 14, 15]) values.length > i ? values[i] : 0.0];

String _fmt(List<double> values) =>
    '[${[for (var i = 0; i < 4; i++) '${_names[i]}=${_f(values[i])}'].join(', ')}]';

String _f(num v) => v.toStringAsFixed(2).padLeft(6);

String _arg(List<String> args, String name, String fallback) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return fallback;
}
