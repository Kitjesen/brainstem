import 'dart:typed_data';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:robo_device_proto/src/can_frame.dart';

import 'internal.dart';

part 'event.freezed.dart';

Uint8List _b(List<int> list) => .fromList(list);

@freezed
sealed class DMG6620Event with _$DMG6620Event {
  const DMG6620Event._();

  factory DMG6620Event.enable(int canId) = DMG6620Enable;
  factory DMG6620Event.disable(int canId) = DMG6620Disable;
  factory DMG6620Event.setZero(int canId) = DMG6620SetZero;
  factory DMG6620Event.clearError(int canId) = DMG6620ClearError;
  factory DMG6620Event.mit(
    int canId, {
    @Default(0.0) double position,
    @Default(0.0) double velocity,
    @Default(0.0) double torque,
    @Default(0.0) double kp,
    @Default(0.0) double kd,
  }) = DMG6620Mit;

  CanFrame toCanFrame() {
    switch (this) {
      case DMG6620Enable():
        return canFrame(
          id: canId,
          data: _b([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfc]),
        );
      case DMG6620Disable():
        return canFrame(
          id: canId,
          data: _b([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfd]),
        );
      case DMG6620SetZero():
        return canFrame(
          id: canId,
          data: _b([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe]),
        );
      case DMG6620ClearError():
        return canFrame(
          id: canId,
          data: _b([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfb]),
        );
      case DMG6620Mit(
        :final position,
        :final velocity,
        :final torque,
        :final kp,
        :final kd,
      ):
        final posUint = floatToUint(position, -positionMax, positionMax, 16);
        final velUint = floatToUint(velocity, -velocityMax, velocityMax, 12);
        final torUint = floatToUint(torque, -torqueMax, torqueMax, 12);
        final kpUint = floatToUint(kp, 0.0, kpMax, 12);
        final kdUint = floatToUint(kd, 0.0, kdMax, 12);
        return canFrame(
          id: canId,
          data: _b([
            posUint >> 8,
            posUint & 0xff,
            (velUint >> 4) & 0xff,
            ((velUint & 0x0f) << 4) | ((kpUint >> 8) & 0x0f),
            kpUint & 0xff,
            kdUint >> 4,
            ((kdUint & 0x0f) << 4) | ((torUint >> 8) & 0x0f),
            torUint & 0xff,
          ]),
        );
    }
  }
}
