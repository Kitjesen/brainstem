import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart';
import 'package:grpc/grpc.dart';

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
    print('before cms kind=${cms.kind.name} transition=${cms.transition.name}');
    if (cms.kind != CmsStateKind.CMS_STATE_KIND_GROUNDED) {
      stderr.writeln('ABORT: SetZero requires Grounded');
      exitCode = 2;
      return;
    }

    await client.setZero(Empty());
    print('SetZero OK');
  } finally {
    await channel.shutdown();
  }
}
