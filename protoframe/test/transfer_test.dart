import 'dart:math';
import 'dart:typed_data';

import 'package:protoframe/protoframe.dart';
import 'package:test/test.dart';

void main() {
  test('encode and decode data frame', () {
    final payload = Uint8List.fromList('Hello, World!'.codeUnits);
    final encoded = encodeProtoFrame(payload);
    final (decoded, rest) = decodeProtoFrame(encoded);
    expect(decoded, [payload]);
    expect(rest, isEmpty);
  });

  test('decode multiple data frames', () {
    final payload1 = Uint8List.fromList('Hello, World!'.codeUnits);
    final payload2 = Uint8List.fromList('Goodbye!'.codeUnits);
    final encoded1 = encodeProtoFrame(payload1);
    final encoded2 = encodeProtoFrame(payload2);
    final combined = Uint8List.fromList([...encoded1, ...encoded2]);
    final (decoded, rest) = decodeProtoFrame(combined);
    expect(decoded, [payload1, payload2]);
    expect(rest, isEmpty);
  });

  test('decode incomplete data frame', () {
    final payload1 = Uint8List.fromList('Hello, World!'.codeUnits);
    final payload2 = Uint8List.fromList('Goodbye!'.codeUnits);
    final encoded1 = encodeProtoFrame(payload1);
    final encoded2 = encodeProtoFrame(payload2);
    final combined = Uint8List.fromList([...encoded1, ...encoded2]);
    final breakPoint = Random().nextInt(encoded1.length);
    final (part1, part2) = (
      combined.sublist(0, breakPoint),
      combined.sublist(breakPoint),
    );
    final (decoded1, rest1) = decodeProtoFrame(part1);
    expect(decoded1, isEmpty);
    expect(rest1, part1);
    final (decoded2, rest2) = decodeProtoFrame(
      Uint8List.fromList([...rest1, ...part2]),
    );
    expect(rest2, isEmpty);
    expect(decoded2, [payload1, payload2]);
  });
}
