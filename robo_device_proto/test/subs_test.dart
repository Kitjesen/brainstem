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

  group('standard SBUS', () {
    test('decodes all 16 packed channels across noise and fragments', () async {
      final channels = <int>[
        282,
        1002,
        1722,
        400,
        500,
        600,
        700,
        800,
        900,
        1000,
        1100,
        1200,
        1300,
        1400,
        1500,
        1600,
      ];
      final frame = _standardSbusFrame(channels);

      final result = await Stream.fromIterable([
        Uint8List.fromList([0x55, 0xAA, ...frame.sublist(0, 7)]),
        Uint8List.fromList(frame.sublist(7, 19)),
        Uint8List.fromList(frame.sublist(19)),
      ]).transform(const StandardSbusChannelDecoder()).toList();

      expect(result.expand((batch) => batch).single.$1, channels);
    });

    test('accepts Futaba telemetry end byte and resynchronizes', () async {
      final first = _standardSbusFrame(List.filled(16, 1002), end: 0x04);
      final secondChannels = List<int>.generate(16, (index) => 300 + index);
      final second = _standardSbusFrame(secondChannels);

      final result = await Stream.value(
        Uint8List.fromList([...first, 0x33, 0x44, ...second]),
      ).transform(const StandardSbusChannelDecoder()).toList();

      expect(result.expand((batch) => batch).map((frame) => frame.$1), [
        List.filled(16, 1002),
        secondChannels,
      ]);
    });

    test(
      'rejects invalid end bytes without losing the following frame',
      () async {
        final invalid = _standardSbusFrame(List.filled(16, 282))..[24] = 0x7F;
        final validChannels = List.filled(16, 1722);
        final valid = _standardSbusFrame(validChannels);

        final result = await Stream.value(
          Uint8List.fromList([...invalid, ...valid]),
        ).transform(const StandardSbusChannelDecoder()).toList();

        expect(result.expand((batch) => batch).single.$1, validChannels);
      },
    );

    test('marks frame-lost and failsafe frames unhealthy', () {
      expect(isStandardSbusHealthy(0x00), isTrue);
      expect(isStandardSbusHealthy(0x04), isFalse);
      expect(isStandardSbusHealthy(0x08), isFalse);
      expect(isStandardSbusHealthy(0x0C), isFalse);
    });
  });
}

Uint8List _standardSbusFrame(List<int> channels, {int flags = 0, int end = 0}) {
  final frame = Uint8List(25)..[0] = 0x0F;
  for (var channel = 0; channel < 16; channel++) {
    final value = channels[channel] & 0x07FF;
    final bitOffset = channel * 11;
    for (var bit = 0; bit < 11; bit++) {
      if ((value & (1 << bit)) != 0) {
        final packedBit = bitOffset + bit;
        frame[1 + packedBit ~/ 8] |= 1 << (packedBit % 8);
      }
    }
  }
  frame[23] = flags;
  frame[24] = end;
  return frame;
}
