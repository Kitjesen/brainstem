import 'dart:typed_data';

import 'package:robo_device_proto/src/subs/state.dart';
import 'package:test/test.dart';

void main() {
  test("parse data", () async {
    final example =
        '0F 03 E8 03 E8 00 00 03 E8 03 E8 03 E8 03 E8 03 E8 04 2C 04 2C 04 2C 04 2C 04 00 04 00 04 00 04'
        ' '
        '00 0C E7';
    final bytes = example
        .split(' ')
        .map((e) => int.parse(e, radix: 16))
        .toList();

    final result = await Stream.value(
      Uint8List.fromList(bytes),
    ).transform(const SubsChannelDecoder()).toList();
    expect(result.length, 1);
    expect(result[0].length, 1);
    final frame = result[0][0];
    expect(frame.$1, [
      1000,
      1000,
      0,
      1000,
      1000,
      1000,
      1000,
      1000,
      1068,
      1068,
      1068,
      1068,
      1024,
      1024,
      1024,
      1024,
    ]);
    expect(frame.$2, 0x0C);
  });
}
