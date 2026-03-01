import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart' as msg;

/// ignore: non_abstract_class_inherits_abstract_member
class CmsExample extends msg.CmsServiceBase {
  @override
  Future<msg.Empty> enable(ServiceCall call, msg.Empty request) async {
    return msg.Empty();
  }

  // @override
  // Stream<msg.Strategy> listenStrategy(
  //   ServiceCall call,
  //   msg.Empty request,
  // ) async* {
  //   for (var i = 0; i < 5; i++) {
  //     yield msg.Strategy(
  //       data: msg.StrategyType.IDLE,
  //       timestamp: msg.Duration.fromDart(Duration(seconds: i)),
  //     );
  //   }
  // }
}

void main() async {
  final server = Server.create(services: [CmsExample()]);
  await server.serve(port: 13145);
}
