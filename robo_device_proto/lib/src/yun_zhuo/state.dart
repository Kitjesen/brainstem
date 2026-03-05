// ignore_for_file: non_constant_identifier_names

import 'package:vector_math/vector_math.dart';

/// SBUS 协议原始值常量
class SbusValues {
  static const int high = 1722; // 高位（开关开、按键按下）
  static const int center = 1002; // 中位（摇杆居中、三档开关中间档）
  static const int low = 282; // 低位（开关关、按键未按）
}

enum GSState {
  up(SbusValues.high),
  middle(SbusValues.center),
  down(SbusValues.low);

  final int value;
  const GSState(this.value);
  factory GSState.fromValue(int value) => values.firstWhere(
    (e) => e.value == value,
    orElse: () => throw ArgumentError('Invalid GSState value: $value'),
  );
}

class YunZhuoState {
  final bool L1;
  final bool L2;
  final bool R1;
  final bool R2;
  final Vector2 leftStick;
  final Vector2 rightStick;
  final bool H;
  final GSState G_S;
  final bool red;
  final bool LT;
  final bool RT;
  final double knob;
  final List<int> rawChannels;

  const YunZhuoState({
    required this.L1,
    required this.L2,
    required this.R1,
    required this.R2,
    required this.leftStick,
    required this.rightStick,
    required this.H,
    required this.G_S,
    required this.red,
    required this.LT,
    required this.RT,
    required this.knob,
    required this.rawChannels,
  });

  factory YunZhuoState.fromChannels(List<int> channels, int flags) {
    return YunZhuoState(
      L1: channels[10] == SbusValues.high,
      L2: channels[6] == SbusValues.high,
      R1: channels[14] == SbusValues.high,
      R2: channels[15] == SbusValues.high,
      leftStick: .new(
        (channels[3] - SbusValues.center) / 720,
        (channels[2] - SbusValues.center) / 720,
      ),
      rightStick: .new(
        (channels[0] - SbusValues.center) / 720,
        -(channels[1] - SbusValues.center) / 720,
      ),
      H: channels[5] == SbusValues.high,
      G_S: GSState.fromValue(channels[4]),
      red: channels[12] == SbusValues.high,
      LT: channels[7] == SbusValues.high,
      RT: channels[11] == SbusValues.high,
      knob: (channels[13] - SbusValues.center) / 720,
      rawChannels: List.unmodifiable(channels),
    );
  }

  @override
  String toString() =>
      '''
L1: $L1, L2: $L2, R1: $R1, R2: $R2
Left Stick: (${leftStick.x.toStringAsFixed(2)}, ${leftStick.y.toStringAsFixed(2)}), 
Right Stick: (${rightStick.x.toStringAsFixed(2)}, ${rightStick.y.toStringAsFixed(2)})
H: $H, G_S: $G_S, red: $red
LT: $LT, RT: $RT, knob: ${knob.toStringAsFixed(2)}
''';
}
