import 'package:robo_device_proto/src/can_frame.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'internal.dart';

part 'state.freezed.dart';

enum DMG6620Status {
  disable(0),
  enable(1),
  overVoltage(8),
  underVoltage(9),
  overCurrent(0xa),
  mosOverTemp(0xb),
  rotorOverTemp(0xc),
  commLost(0xd),
  overload(0xe);

  final int value;
  const DMG6620Status(this.value);

  static DMG6620Status fromValue(int n) {
    return values.firstWhere(
      (status) => status.value == n,
      orElse: () => throw Exception('Unknown G6620Status value: $n'),
    );
  }
}

@freezed
abstract class DMG6620State with _$DMG6620State {
  factory DMG6620State({
    required int hostId,
    required int canId,
    required DMG6620Status status,
    required double position,
    required double velocity,
    required double torque,
    required double temperatureMos,
    required double temperatureRotor,
  }) = _DMG6620State;

  factory DMG6620State.fromCanFrame(CanFrame frame) {
    if (frame.data.length < 8) {
      throw ArgumentError(
        'DMG6620State: CAN frame data too short '
        '(${frame.data.length} < 8)',
      );
    }
    return .new(
    hostId: frame.id,
    canId: frame.data[0] & 0x0f,
    status: .fromValue(frame.data[0] >> 4),
    position: uintToFloat(
      frame.data[1] << 8 | frame.data[2],
      -positionMax,
      positionMax,
      16,
    ),
    velocity: uintToFloat(
      frame.data[3] << 4 | frame.data[4] >> 4,
      -velocityMax,
      velocityMax,
      12,
    ),
    torque: uintToFloat(
      (frame.data[4] & 0x0f) << 8 | frame.data[5],
      -torqueMax,
      torqueMax,
      12,
    ),
    temperatureMos: frame.data[6].toDouble(),
    temperatureRotor: frame.data[7].toDouble(),
  );
  }
}
