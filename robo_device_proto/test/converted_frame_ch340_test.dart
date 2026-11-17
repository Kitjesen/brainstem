import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

void main() {
  test('converter frame preserves channels and rejects a bad checksum', () async {
    final channels = [1002, 1002, 1002, 1002, 1002, 282, 282, 1722,
      282, 282, 282, 282, 282, 1002, 282, 1722];
    final bytes = ByteData(35)..setUint8(0, 15);
    for (var i = 0; i < channels.length; i++) {
      bytes.setUint16(1 + i * 2, channels[i]);
    }
    var crc = 0;
    for (var i = 1; i < 34; i++) { crc ^= bytes.getUint8(i); }
    bytes.setUint8(34, crc);
    final frame = bytes.buffer.asUint8List();
    final decoded = await const SubsChannelDecoder().bind(Stream.value(frame)).single;
    expect(decoded.single.$1, channels);
    expect(isStandardSbusHealthy(decoded.single.$2), isTrue);
    frame[34] ^= 1;
    final bad = await const SubsChannelDecoder().bind(Stream.value(frame)).single;
    expect(bad, isEmpty);
  });
}
