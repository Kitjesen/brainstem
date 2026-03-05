import 'dart:async';
import 'dart:typed_data';

import 'data.dart';

Uint8List encodeProtoFrame(Uint8List payload) {
  final dataFrame = DataFrame();
  dataFrame.payload = payload;
  dataFrame.length = payload.length;
  dataFrame.crcHeader = [
    sync1,
    sync2,
    dataFrame.length & 0xFF,
    (dataFrame.length >> 8) & 0xFF,
  ];
  dataFrame.crc = dataFrame.calculateCrc();
  return dataFrame.toBytes();
}

class ProtoframeEncoder extends StreamTransformerBase<Uint8List, Uint8List> {
  const ProtoframeEncoder();
  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) => stream.map(convert);
  Uint8List convert(Uint8List payload) => encodeProtoFrame(payload);
}
