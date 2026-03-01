import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart' as msg;

void main() async {
  final channel = ClientChannel(
    'localhost',
    port: 13145,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  final stub = msg.CmsClient(channel);
  final response = await stub.enable(msg.Empty());
  print('Enable response: $response');
  // await for (var status in stub.listenStrategy(msg.Empty())) {
  //   print('Strategy: ${status.data}, Timestamp: ${status.timestamp.toDart()}');
  // }
  await channel.shutdown();
}
