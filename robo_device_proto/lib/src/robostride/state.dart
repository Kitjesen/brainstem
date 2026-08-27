import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:robo_device_proto/src/can_frame.dart';

import 'type.dart';
import 'parameter.dart';
import 'internal.dart';
import 'error.dart';
import 'motor_config.dart';

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
    // 0x01: motion control ACK (motor echoes back the control command)
    // 0x02: general motor response
    // Both share identical data2/data1 layout: position, velocity, torque,
    // temperature in data1; canId, errors, status packed in data2.
    0x01 || 0x02 => _motionState(frame, isReport: false),
    0x18 => _motionState(frame, isReport: true),
    0x11 => .getter(
      hostId: frame.canId,
      canId: frame.data2 & 0xFF,
      getter: ((frame.data2 >> 8) & 0xFF) == 0x00
          ? RSGetter.tryFromByteData(frame.bytes)
          : null,
    ),
    0x15 => .error(
      hostId: frame.canId,
      canId: frame.data2 & 0xFF,
      errors: .new(frame.data2),
    ),
    _ => throw UnimplementedError(
      'Unknown RSState mode: 0x${frame.mode.toRadixString(16)}',
    ),
  };

  factory RSState.fromCanFrame(CanFrame frame) =>
      .fromDataFrame(.fromCanFrame(frame));
}

RSState _motionState(RSDataFrame frame, {required bool isReport}) {
  final canId = frame.data2 & 0xFF;
  final limits = rsMotorLimitsForCanId(canId);
  final position = uint16ToFloat(
    frame.bytes.getUint16(0),
    -positionMax,
    positionMax,
  );
  final velocity = uint16ToFloat(
    frame.bytes.getUint16(2),
    -limits.velocityMax,
    limits.velocityMax,
  );
  final torque = uint16ToFloat(
    frame.bytes.getUint16(4),
    -limits.torqueMax,
    limits.torqueMax,
  );
  final temperature = frame.bytes.getUint16(6) / 10.0;
  final status = RSStatus.fromValue((frame.data2 >> 14) & 0x3);
  final errors = RSErrors1((frame.data2 >> 8) & 0x3F);

  return isReport
      ? RSState.report(
          canId: canId,
          hostId: frame.canId,
          position: position,
          velocity: velocity,
          torque: torque,
          temperature: temperature,
          status: status,
          errors: errors,
        )
      : RSState.response(
          canId: canId,
          hostId: frame.canId,
          position: position,
          velocity: velocity,
          torque: torque,
          temperature: temperature,
          status: status,
          errors: errors,
        );
}
