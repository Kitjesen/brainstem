import 'dart:typed_data';

import 'package:meta/meta.dart';

enum ParserState {
  head1, // 寻找帧头第一个字节
  head2, // 验证帧头第二个字节
  parseLength, // 解析数据长度
  crc,
  data, // 有效数据
  checkCode, // 校验
}

const int sync1 = 0x5A, sync2 = 0xA5;
const int headerSize = 2 + 2 + 2;
const int crcSize = 2;
const int maxPayload = 65536 - 20;

class DataFrame {
  List<int> crcHeader = [];
  int length = 0;
  int crc = 0;
  Uint8List payload = Uint8List(0);

  void clear() {
    crcHeader = [];
    length = 0;
    crc = 0;
    payload = Uint8List(0);
  }

  int calculateCrc() => checkCode(crcHeader, payload);

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(crcHeader);
    buffer.add([crc & 0xFF, (crc >> 8) & 0xFF]);
    buffer.add(payload);
    return buffer.toBytes();
  }
}

int checkCode(List<int> header, List<int> data) {
  return crc16(crc16(0, Uint8List.fromList(header)), Uint8List.fromList(data));
}

@visibleForTesting
int crc16(int crc, Uint8List data) {
  for (int i = 0; i < data.length; i++) {
    final byte = data[i];
    crc ^= byte << 8;
    for (int j = 0; j < 8; j++) {
      var temp = crc << 1;
      if (crc & 0x8000 != 0) {
        temp ^= 0x1021;
      }
      crc = temp;
    }
  }
  return crc & 0xFFFF;
}
