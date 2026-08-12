import 'dart:typed_data';

import 'package:robo_device_proto/src/subs/state.dart';
import 'package:test/test.dart';

void main() {
  test('parse custom 35-byte data', () async {
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

  test('parse fragmented standard SBUS data and resynchronize', () async {
    const example =
        '0F EA 53 9F FA D4 A7 6B 8D 68 44 23 1A D1 88 46 34 A2 11 F5 69 44 23 00 00';
    final frameBytes = example
        .split(' ')
        .map((e) => int.parse(e, radix: 16))
        .toList();

    final chunks = <Uint8List>[
      Uint8List.fromList([0xAA, 0x55, ...frameBytes.take(7)]),
      Uint8List.fromList(frameBytes.skip(7).take(9).toList()),
      Uint8List.fromList(frameBytes.skip(16).toList()),
    ];
    final result = await Stream.fromIterable(
      chunks,
    ).transform(const StandardSbusChannelDecoder()).toList();

    expect(result, hasLength(1));
    expect(result.single, hasLength(1));
    final frame = result.single.single;
    expect(frame.$1, [
      1002,
      1002,
      1002,
      1002,
      1722,
      282,
      282,
      282,
      282,
      282,
      282,
      282,
      282,
      1002,
      282,
      282,
    ]);
    expect(frame.$2, 0);
    expect(isStandardSbusHealthy(frame.$2), isTrue);
    expect(isStandardSbusHealthy(1 << 2), isFalse);
    expect(isStandardSbusHealthy(1 << 3), isFalse);
  });
}
