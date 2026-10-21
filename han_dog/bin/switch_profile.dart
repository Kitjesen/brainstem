import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart';
import 'package:grpc/grpc.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/switch_profile.dart PROFILE_NAME');
    exitCode = 2;
    return;
  }

  final channel = ClientChannel(
    '127.0.0.1',
    port: 13145,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  final client = RobotControlClient(channel);
  try {
    final state = await client.getCmsState(Empty());
    print('state_before=${state.kind.name}');
    final before = await client.getProfile(Empty());
    print('profile_before=${before.current}');

    final switched = await client.switchProfile(ProfileRequest(name: args.single));
    print('profile_switch_result=${switched.current}');

    final after = await client.getProfile(Empty());
    print('profile_after=${after.current}');
    final stateAfter = await client.getCmsState(Empty());
    print('state_after=${stateAfter.kind.name}');
  } finally {
    await channel.shutdown();
  }
}
