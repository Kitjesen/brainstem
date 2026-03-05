import 'dart:typed_data';

class CanFrame {
  final int id;
  final CanType type;
  final Uint8List data;
  const CanFrame({required this.id, required this.data, required this.type});
  int get length => data.length;

  @override
  String toString() =>
      '$type: ${_bInt(id)} |${_bInt(length, 2)}| ${_bStr(data)}';
}

enum CanType {
  standard,
  extended;

  @override
  String toString() => switch (this) {
    standard => 'std',
    extended => 'ext',
  };
}

String _bStr(Uint8List data) =>
    data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
String _bInt(int value, [int width = 8]) =>
    value.toRadixString(16).padLeft(width, '0');
