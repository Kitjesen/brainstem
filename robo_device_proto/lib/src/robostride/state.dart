import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:robo_device_proto/src/can_frame.dart';

import 'type.dart';
import 'parameter.dart';
import 'internal.dart';
import 'error.dart';

part 'state.freezed.dart';

@freezed
sealed class RSState with _$RSState {
  const RSState._();

  factory RSState.deviceId({required int canId, required BigInt mcuId}) =
      RSStateDeviceId;
  factory RSState.response({
    required int hostId,
    required int canId,
    required RSStatus status,
    required double position,
    required double velocity,
    required double torque,
    required double temperature,
    required RSErrors1 errors,
  }) = RSStateResponse;
  factory RSState.report({
    required int hostId,
    required int canId,
    required RSStatus status,
    required double position,
    required double velocity,
    required double torque,
    required double temperature,
    required RSErrors1 errors,
  }) = RSStateReport;
  factory RSState.getter({
    required int hostId,
    required int canId,
    RSGetter? getter,
  }) = RSStateGetter;
  factory RSState.error({
    required int hostId,
    required int canId,
    required RSErrors2 errors,
  }) = RSStateError;

  @visibleForTesting
  factory RSState.fromDataFrame(RSDataFrame frame) => switch (frame.mode) {
    0x00 => .deviceId(
      canId: frame.data2,
      mcuId: .parse(
        frame.data1.map((b) => b.toRadixString(10).padLeft(2, '0')).join(),
        radix: 10,
      ),
    ),
    0x02 => .response(
      canId: (frame.data2) & 0xFF,
      hostId: frame.canId,
      position: uint16ToFloat(
        frame.bytes.getUint16(0),
        -positionMax,
        positionMax,
      ),
      velocity: uint16ToFloat(
        frame.bytes.getUint16(2),
        -velocityMax,
        velocityMax,
      ),
      torque: uint16ToFloat(frame.bytes.getUint16(4), -torqueMax, torqueMax),
      temperature: frame.bytes.getUint16(6) / 10.0,
      status: .fromValue((frame.data2 >> 14) & 0x3),
      errors: .new((frame.data2 >> 8) & 0x3F),
    ),
    0x18 => .report(
      canId: (frame.data2) & 0xFF,
      hostId: frame.canId,
      position: uint16ToFloat(
        frame.bytes.getUint16(0),
        -positionMax,
        positionMax,
      ),
      velocity: uint16ToFloat(
        frame.bytes.getUint16(2),
        -velocityMax,
        velocityMax,
      ),
      torque: uint16ToFloat(frame.bytes.getUint16(4), -torqueMax, torqueMax),
      temperature: frame.bytes.getUint16(6) / 10.0,
      status: .fromValue((frame.data2 >> 14) & 0x3),
      errors: .new((frame.data2 >> 8) & 0x3F),
    ),
    0x11 => .getter(
      hostId: frame.canId,
      canId: frame.data2 & 0xFF,
      getter: ((frame.data2 >> 8) & 0xFF) == 0x00
          ? .fromByteData(frame.bytes)
          : null,
    ),
    0x15 => .error(
      hostId: frame.canId,
      canId: frame.data2 & 0xFF,
      errors: .new(frame.data2),
    ),
    _ => throw Exception('Unknown RSState mode: ${frame.mode}'),
  };

  factory RSState.fromCanFrame(CanFrame frame) =>
      .fromDataFrame(.fromCanFrame(frame));
}
