import 'package:pcan/pcan.dart';
import 'package:pcan/src/socketcan.dart';
import 'package:test/test.dart';

void main() {
  test('explicit SocketCAN never falls through to PCAN Basic before open', () {
    final pcan = Pcan.socketCan(PcanChannel.usbbus2);
    expect(pcan.read().$3, PcanStatus.illhw);
    expect(pcan.close(), PcanStatus.ok);
  });
  test(
    'errno distinguishes backpressure from broken interfaces and bad data',
    () {
      for (final e in [4, 11, 105]) {
        expect(socketCanWriteStatus(e), PcanStatus.xmtfull);
      }
      expect(socketCanWriteStatus(100), PcanStatus.busoff);
      expect(socketCanWriteStatus(19), PcanStatus.illhw);
      expect(socketCanWriteStatus(22), PcanStatus.illdata);
      expect(socketCanWriteStatus(90), PcanStatus.illdata);
      expect(socketCanWriteStatus(12345), PcanStatus.unknown);
    },
  );
}
