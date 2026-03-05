import 'dart:math';
import 'dart:typed_data';

import 'package:protoframe/protoframe.dart';
import 'package:test/test.dart';

void main() {
  test('basic stream encode and decode round-trip', () {
    // Test basic functionality: encode a payload through encoder stream,
    // then decode it through decoder stream, ensuring round-trip works
    final payload = Uint8List.fromList('Hello, World!'.codeUnits);
    expectLater(
      protoframe.encoder
          .bind(Stream.value(payload))
          .transform(protoframe.decoder),
      emits([payload]),
    );
  });

  test('decode multiple frames from single stream chunk', () {
    // Test decoder's ability to parse multiple complete frames
    // that arrive together in a single stream chunk
    final payload1 = Uint8List.fromList('Hello, World!'.codeUnits);
    final payload2 = Uint8List.fromList('Goodbye!'.codeUnits);

    expectLater(
      Stream.value(
        Uint8List.fromList([
          ...encodeProtoFrame(payload1),
          ...encodeProtoFrame(payload2),
        ]),
      ).transform(protoframe.decoder),
      emits([payload1, payload2]), // Should decode both frames at once
    );
  });

  test('handle fragmented frames across stream chunks', () {
    // Test decoder's state management when frames are split across
    // multiple stream chunks (simulates real-world network conditions)
    final payload1 = Uint8List.fromList('Hello, World!'.codeUnits);
    final payload2 = Uint8List.fromList('Goodbye!'.codeUnits);

    expectLater(
      () async* {
        final encoded1 = encodeProtoFrame(payload1);
        final encoded2 = encodeProtoFrame(payload2);
        final combined = Uint8List.fromList([...encoded1, ...encoded2]);

        // Randomly split the data to simulate fragmented network packets
        final breakPoint = Random().nextInt(encoded1.length);
        final (part1, part2) = (
          combined.sublist(0, breakPoint), // Incomplete first frame
          combined.sublist(breakPoint), // Rest of first + complete second frame
        );
        yield part1; // First chunk: incomplete frame
        yield part2; // Second chunk: completes frames
      }().transform(protoframe.decoder),

      emitsInOrder([
        [], // First chunk yields no complete frames
        [payload1, payload2], // Second chunk yields both complete frames
      ]),
    );
  });
}
