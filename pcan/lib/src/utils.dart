import 'dart:convert';
import 'dart:typed_data';
import 'pcan_basic.dart';
import 'dart:ffi' as ffi;

extension IntExt on int {
  String toHex() => toRadixString(16).padLeft(8, '0').toUpperCase();
  PcanStatus get asPcanStatus => .fromValue(this);
}

extension Uint8ListExt on Uint8List {
  String toHex() => map(
    (byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
  ).join(' ');
}

/// https://documentation.help/PCAN-Basic/TPCANMsgFD.html
int lengthToDlc(int length) => switch (length) {
  <= 8 => length,
  12 => 9,
  16 => 10,
  20 => 11,
  24 => 12,
  32 => 13,
  48 => 14,
  64 => 15,
  _ => throw ArgumentError('Invalid CAN FD length: $length'),
};

int dlcToLength(int dlc) => switch (dlc) {
  <= 8 => dlc,
  9 => 12,
  10 => 16,
  11 => 20,
  12 => 24,
  13 => 32,
  14 => 48,
  15 => 64,
  _ => throw ArgumentError('Invalid CAN FD DLC: $dlc'),
};

/// https://github.com/aeb-dev/steamworks/issues/6
extension CharExt on ffi.Array<ffi.Char> {
  String toDartString() {
    final bytesBuilder = BytesBuilder();
    for (int index = 0; this[index] != 0; index++) {
      bytesBuilder.addByte(this[index]);
    }
    final bytes = bytesBuilder.takeBytes();
    return utf8.decode(bytes);
  }
}
