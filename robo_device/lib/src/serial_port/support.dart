import 'dart:typed_data';

import 'package:protoframe/protoframe.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

final stateConverter = <Type, Function>{
  QPYunZhuoState: (Stream<Uint8List> stream) => protoframe.decoder
      .bind(stream)
      .map((frames) => frames.map(QPYunZhuoState.fromBytes)),
  Hi91State: (Stream<Uint8List> stream) => protoframe.decoder
      .bind(stream)
      .map((frames) => frames.map(Hi91State.fromBytes)),
  YunZhuoState: (Stream<Uint8List> stream) => const SubsChannelDecoder()
      .bind(stream)
      .map(
        (frames) => frames.map(
          (frame) => YunZhuoState.fromChannels(frame.$1, frame.$2),
        ),
      ),
};

final eventConverter = {QPYunZhuoEvent: (QPYunZhuoEvent event) => Uint8List(0)};
