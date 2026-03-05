import 'dart:typed_data';

import 'decode.dart';
import 'encode.dart';

const protoframe = ProtoFrame();

class ProtoFrame {
  const ProtoFrame();
  ProtoframeDecoder get decoder => const ProtoframeDecoder();
  ProtoframeEncoder get encoder => const ProtoframeEncoder();
  Uint8List encode(Uint8List payload) =>
      const ProtoframeEncoder().convert(payload);
}
