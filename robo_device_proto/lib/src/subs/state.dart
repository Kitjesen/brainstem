import 'dart:async';
import 'dart:typed_data';

const frameSize = 35;
const frameRestLength = 34;
const syncCode = 0x0F;
const standardSbusFrameSize = 25;
const standardSbusFlagsOffset = 23;
const standardSbusEndOffset = 24;
const standardSbusFrameLostFlag = 1 << 2;
const standardSbusFailsafeFlag = 1 << 3;

bool isStandardSbusHealthy(int flags) =>
    (flags & (standardSbusFrameLostFlag | standardSbusFailsafeFlag)) == 0;

bool _isStandardSbusEndByte(int byte) =>
    byte == 0 || (byte & 0x0F) == 0x04;

List<int> _unpackStandardSbusChannels(List<int> frame) {
  return List<int>.generate(16, (channel) {
    final bitOffset = channel * 11;
    var value = 0;
    for (var bit = 0; bit < 11; bit++) {
      final packedBit = bitOffset + bit;
      final byte = frame[1 + packedBit ~/ 8];
      value |= ((byte >> (packedBit % 8)) & 1) << bit;
    }
    return value;
  }, growable: false);
}

class StandardSbusChannelDecoder
    extends StreamTransformerBase<Uint8List, List<(List<int>, int)>> {
  const StandardSbusChannelDecoder();

  @override
  Stream<List<(List<int>, int)>> bind(Stream<Uint8List> stream) async* {
    final pending = <int>[];
    await for (final chunk in stream) {
      pending.addAll(chunk);
      final frames = <(List<int>, int)>[];
      while (true) {
        final start = pending.indexOf(syncCode);
        if (start < 0) {
          pending.clear();
          break;
        }
        if (start > 0) pending.removeRange(0, start);
        if (pending.length < standardSbusFrameSize) break;
        if (!_isStandardSbusEndByte(pending[standardSbusEndOffset])) {
          pending.removeAt(0);
          continue;
        }
        final frame = pending.sublist(0, standardSbusFrameSize);
        frames.add((
          _unpackStandardSbusChannels(frame),
          frame[standardSbusFlagsOffset],
        ));
        pending.removeRange(0, standardSbusFrameSize);
      }
      if (frames.isNotEmpty) yield frames;
    }
  }
}

class DataFrame {
  int head = 0;
  List<int> channels = List.filled(16, 0);
  int flags = 0;
  int xor = 0;

  Uint8List toBytes() {
    final byteData = ByteData(frameSize);
    byteData.setUint8(0, head);
    for (int i = 0; i < 16; i++) {
      byteData.setUint16(1 + i * 2, channels[i]);
    }
    byteData.setUint8(33, flags);
    byteData.setUint8(34, xor);
    return byteData.buffer.asUint8List();
  }
}

enum ParserState {
  head, // 寻找帧头第一个字节
  data, // 有效数据
  checkCode, // 校验
}

(List<(List<int>, int)>, Uint8List) decodeSubsChannel(Uint8List chunk) {
  int offset = 0;

  int startOffset = 0;

  final List<(List<int>, int)> results = [];
  parsing:
  while ((startOffset + frameSize) <= chunk.length) {
    offset = startOffset;
    final frame = DataFrame();
    ParserState state = .head;
    List<int> examBytes = [];
    newFrame:
    while (true) {
      switch (state) {
        case .head:
          if (offset >= chunk.length) {
            break parsing;
          }
          if (chunk[offset] != syncCode) {
            startOffset++;
            break newFrame;
          }
          state = .data;
          startOffset = offset;
          frame.head = syncCode;
          offset++;
        case .data:
          if (offset + frameRestLength > chunk.length) {
            break parsing;
          }
          final rest = chunk.sublist(offset, offset + frameRestLength);
          final byteView = ByteData.sublistView(rest);
          for (int i = 0; i < 16; i++) {
            frame.channels[i] = byteView.getUint16(i * 2);
          }
          frame.flags = rest[32];
          frame.xor = rest[33];
          examBytes = rest.take(frameRestLength - 1).toList();
          state = .checkCode;
          offset += frameRestLength;
        case .checkCode:
          final crc = checkCode(examBytes);
          if (crc == frame.xor) {
            final result = (frame.channels, frame.flags);
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

class SubsChannelDecoder
    extends StreamTransformerBase<Uint8List, List<(List<int>, int)>> {
  const SubsChannelDecoder();
  @override
  Stream<List<(List<int>, int)>> bind(Stream<Uint8List> stream) async* {
    var lastRest = Uint8List(0);
    await for (final chunk in stream) {
      final (frames, rest) = decodeSubsChannel(
        Uint8List.fromList([...lastRest, ...chunk]),
      );
      lastRest = rest;
      yield frames;
    }
  }
}

int checkCode(List<int> payload) =>
    payload.reduce((value, element) => value ^ element);
