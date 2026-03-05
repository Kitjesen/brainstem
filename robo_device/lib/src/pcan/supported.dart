import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:pcan/pcan.dart';

final eventConverter = {
  RSEvent: (RSEvent event) => event.toCanFrame().toPcanMessage(),
  DMG6620Event: (DMG6620Event event) => event.toCanFrame().toPcanMessage(),
};

final stateConverter = {
  RSState: (PcanMessage message) => RSState.fromCanFrame(message.toCanFrame()),
  DMG6620State: (PcanMessage message) =>
      DMG6620State.fromCanFrame(message.toCanFrame()),
};

extension on PcanMessage {
  CanFrame toCanFrame() => .new(
    id: id,
    type: switch (type) {
      .extended => .extended,
      .standard => .standard,
      _ => throw Exception('Unknown PCAN message type: $type'),
    },
    data: data,
  );
}

extension on CanFrame {
  PcanMessage toPcanMessage() => .new(
    id: id,
    type: switch (type) {
      .extended => .extended,
      .standard => .standard,
    },
    data: data,
  );
}
