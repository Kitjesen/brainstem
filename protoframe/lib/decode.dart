import 'dart:async';
import 'dart:typed_data';

import 'data.dart';

(List<Uint8List>, Uint8List) decodeProtoFrame(Uint8List chunk) {
  int offset = 0;

  int startOffset = 0;

  final List<Uint8List> results = [];
  parsing:
  while ((startOffset + headerSize - 1) < chunk.length) {
    offset = startOffset;
    final frame = DataFrame();
    ParserState state = .head1;
    newFrame:
    while (true) {
      switch (state) {
        case .head1:
          if (offset >= chunk.length) {
            break parsing;
          }
          if (chunk[offset] != sync1) {
            startOffset++;
            break newFrame;
          }
          state = .head2;
          startOffset = offset;
          frame.crcHeader.add(sync1);
          offset++;

        case .head2:
          if (offset >= chunk.length) {
            break parsing;
          }
          if (chunk[offset] != sync2) {
            startOffset++;
            break newFrame;
          }
          state = .parseLength;
          frame.crcHeader.add(sync2);
          offset++;

        case .parseLength:
          if (offset + 2 > chunk.length) {
            break parsing;
          }
          frame.length = chunk[offset] | (chunk[offset + 1] << 8);
          if (frame.length < 0 || frame.length > maxPayload) {
            startOffset++;
            break newFrame;
          }
          state = .crc;
          frame.crcHeader.addAll(chunk.sublist(offset, offset + 2));
          offset += 2;
        case .crc:
          if (offset + crcSize > chunk.length) {
            break parsing;
          }
          frame.crc = chunk[offset] | (chunk[offset + 1] << 8);
          state = .data;
          offset += crcSize;
        case .data:
          if (offset + frame.length > chunk.length) {
            break parsing;
          }
          frame.payload = Uint8List.fromList(
            chunk.sublist(offset, offset + frame.length),
          );
          state = .checkCode;
          offset += frame.length;
        case .checkCode:
          final crc = checkCode(frame.crcHeader, frame.payload);
          if (crc == frame.crc) {
            final result = frame.payload;
            results.add(result);
            startOffset = offset;
          } else {
            startOffset++;
          }
          break newFrame;
      }
    }
  }

  // 保存未处理的剩余数据
  final rest = startOffset < chunk.length
      ? chunk.sublist(startOffset)
      : Uint8List(0);

  return (results, rest);
}

class ProtoframeDecoder
    extends StreamTransformerBase<Uint8List, List<Uint8List>> {
  const ProtoframeDecoder();
  @override
  Stream<List<Uint8List>> bind(Stream<Uint8List> stream) async* {
    var lastRest = Uint8List(0);
    await for (final chunk in stream) {
      final (frames, rest) = decodeProtoFrame(
        Uint8List.fromList([...lastRest, ...chunk]),
      );
      lastRest = rest;
      yield frames;
    }
  }
}
