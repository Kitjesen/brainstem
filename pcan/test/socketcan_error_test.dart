import 'package:pcan/pcan.dart';
import 'package:pcan/src/socketcan.dart';
import 'package:test/test.dart';

void main() {
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
