import 'dart:typed_data';

typedef QPYunZhuoEvent = Never;

class QPYunZhuoState {
  final List<int> ch1Toch16;
  final int ch17;
  final int ch18;
  final int frameLost;
  final int failSafe;

  const QPYunZhuoState({
    required this.ch1Toch16,
    required this.ch17,
    required this.ch18,
    required this.frameLost,
    required this.failSafe,
  });

  factory QPYunZhuoState.fromBytes(Uint8List bytes) {
    if (bytes.length < 36) {
      throw ArgumentError(
        'QPYunZhuoState: data too short (${bytes.length} < 36)',
      );
    }
    final data = ByteData.sublistView(bytes);
    return QPYunZhuoState(
      ch1Toch16: .generate(16, (i) => data.getUint16(i * 2, .little)),
      ch17: data.getUint8(32),
      ch18: data.getUint8(33),
      frameLost: data.getUint8(34),
      failSafe: data.getUint8(35),
    );
  }

  @override
  String toString() {
    return 'ch1Toch16: $ch1Toch16,'
        'ch17: $ch17, ch18: $ch18, '
        'frameLost: $frameLost, failSafe: $failSafe';
  }
}
