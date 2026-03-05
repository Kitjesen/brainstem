import 'dart:typed_data';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:robo_device_proto/src/can_frame.dart';

import 'type.dart';
import 'parameter.dart';
import 'internal.dart';

part 'event.freezed.dart';

const _defaultHostId = 0xff;

Uint8List _b(List<int> list) => .fromList(list);

@freezed
sealed class RSEvent with _$RSEvent {
  const RSEvent._();

  factory RSEvent.getDeviceId(
    int canId, {
    @Default(_defaultHostId) int hostId,
  }) = RSEventGetDeviceId;
  factory RSEvent.control(
    int canId, {
    @Default(0.0) double torque, // (-120Nm~120Nm)
    @Default(0.0) double position, // (-12.57f~12.57f)
    @Default(0.0) double velocity, // (-15rad/s~15rad/s)
    @Default(0.0) double kp, // (0.0~5000.0)
    @Default(0.0) double kd, // (0.0~100.0)
  }) = RSEventControl;
  factory RSEvent.enable(int canId, {@Default(_defaultHostId) int hostId}) =
      RSEventEnable;
  factory RSEvent.disable(
    int canId, {
    @Default(_defaultHostId) int hostId,
    @Default(false) bool clearErrors,
  }) = RSEventDisable;
  factory RSEvent.calibration(int canId) = RSEventCalibration;
  factory RSEvent.setZero(int canId, {@Default(_defaultHostId) int hostId}) =
      RSEventSetZero;
  factory RSEvent.setId(
    int canId, {
    @Default(_defaultHostId) int hostId,
    required int newId,
  }) = RSEventSetId;
  factory RSEvent.get(
    int canId, {
    @Default(_defaultHostId) int hostId,
    required RSKey key,
  }) = RSEventGet;
  factory RSEvent.set(
    int canId, {
    @Default(_defaultHostId) int hostId,
    required RSSetter setter,
  }) = RSEventSet;
  factory RSEvent.saveData(int canId, {@Default(_defaultHostId) int hostId}) =
      RSEventSaveData;
  factory RSEvent.setBaudRate(
    int canId, {
    @Default(_defaultHostId) int hostId,
    required RSBaudRate baudRate,
  }) = RSEventSetBaudRate;
  factory RSEvent.setReporting(
    int canId, {
    @Default(_defaultHostId) int hostId,
    @Default(false) bool enable,
  }) = RSEventSetReporting;
  factory RSEvent.setProtocol(
    int canId, {
    @Default(_defaultHostId) int hostId,
    required RSProtocol protocol,
  }) = RSEventSetProtocol;

  @visibleForTesting
  RSDataFrame toDataFrame() => switch (this) {
    RSEventGetDeviceId(:final canId, :final hostId) => .new(
      mode: 0x00,
      data2: hostId,
      canId: canId,
    ),
    RSEventControl(
      :final canId,
      :final torque,
      :final position,
      :final velocity,
      :final kp,
      :final kd,
    ) =>
      .new(
        mode: 0x01,
        data2: floatToUint16(torque, -torqueMax, torqueMax),
        canId: canId,
        data1:
            (ByteData(8)
                  ..setUint16(
                    0,
                    floatToUint16(position, -positionMax, positionMax),
                  )
                  ..setUint16(
                    2,
                    floatToUint16(velocity, -velocityMax, velocityMax),
                  )
                  ..setUint16(4, floatToUint16(kp, 0.0, kpMax))
                  ..setUint16(6, floatToUint16(kd, 0.0, kdMax)))
                .buffer
                .asUint8List(),
      ),
    RSEventEnable(:final canId, :final hostId) => .new(
      mode: 0x03,
      data2: hostId,
      canId: canId,
    ),
    RSEventDisable(:final canId, :final hostId, :final clearErrors) => .new(
      mode: 0x04,
      data2: hostId,
      canId: canId,
      data1: _b([if (clearErrors) 1 else 0, 0, 0, 0, 0, 0, 0, 0]),
    ),
    RSEventCalibration(:final canId) => .new(
      mode: 0x05,
      data2: 0xfd,
      canId: canId,
    ),
    RSEventSetZero(:final canId, :final hostId) => .new(
      mode: 0x06,
      data2: hostId,
      canId: canId,
      data1: _b([1, 0, 0, 0, 0, 0, 0, 0]),
    ),
    RSEventSetId(:final canId, :final newId, :final hostId) => .new(
      mode: 0x07,
      data2: hostId | (newId << 8),
      canId: canId,
    ),
    RSEventGet(:final canId, :final key, :final hostId) => .new(
      mode: 0x11,
      data2: hostId,
      canId: canId,
      data1: key.toByteData().buffer.asUint8List(),
    ),
    RSEventSet(:final canId, :final setter, :final hostId) => .new(
      mode: 0x12,
      data2: hostId,
      canId: canId,
      data1: setter.toByteData().buffer.asUint8List(),
    ),
    RSEventSaveData(:final canId, :final hostId) => .new(
      mode: 0x16,
      data2: hostId,
      canId: canId,
      data1: _b([1, 2, 3, 4, 5, 6, 7, 8]),
    ),
    RSEventSetBaudRate(:final canId, :final baudRate, :final hostId) => .new(
      mode: 0x17,
      data2: hostId,
      canId: canId,
      data1: _b([1, 2, 3, 4, 5, 6, baudRate.value, 0]),
    ),
    RSEventSetReporting(:final canId, :final enable, :final hostId) => .new(
      mode: 0x18,
      data2: hostId,
      canId: canId,
      data1: _b([1, 2, 3, 4, 5, 6, enable ? 1 : 0, 0]),
    ),
    RSEventSetProtocol(:final canId, :final protocol, :final hostId) => .new(
      mode: 0x19,
      data2: hostId,
      canId: canId,
      data1: _b([1, 2, 3, 4, 5, 6, protocol.value, 0]),
    ),
  };

  CanFrame toCanFrame() => toDataFrame().toCanFrame();
}
