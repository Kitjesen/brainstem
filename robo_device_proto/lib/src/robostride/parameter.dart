import 'dart:typed_data';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'type.dart';

part 'parameter.freezed.dart';

enum RSKey {
  runMode(0x7005),
  iqRef(0x7006),
  spdRef(0x700A),
  limitTorque(0x700B),
  curKp(0x7010),
  curKi(0x7011),
  curFiltGain(0x7014),
  locRef(0x7016),
  limitSpd(0x7017),
  limitCur(0x7018),
  mechPos(0x7019),
  iqf(0x701A),
  mechVel(0x701B),
  vbus(0x701C),
  locKp(0x701E),
  spdKp(0x701F),
  spdKi(0x7020),
  spdFiltGain(0x7021),
  accRad(0x7022),
  velMax(0x7024),
  accSet(0x7025),
  epscanTime(0x7026),
  cantimeout(0x7028),
  zeroSta(0x7029);

  final int value;
  const RSKey(this.value);

  factory RSKey.fromValue(int value) {
    return values.firstWhere(
      (key) => key.value == value,
      orElse: () => throw Exception("Unknown MotorParameterMeta code: $value"),
    );
  }

  ByteData toByteData() => ByteData(8)..setUint16(0, value, .little);
  factory RSKey.fromByteData(ByteData data) =>
      RSKey.fromValue(data.getUint16(0, .little));
}

@freezed
sealed class RSGetter with _$RSGetter {
  const RSGetter._();

  factory RSGetter.runMode(RSRunMode value) = RSGetterRunMode;
  factory RSGetter.iqRef(double value) = RSGetterIqRef;
  factory RSGetter.spdRef(double value) = RSGetterSpdRef;
  factory RSGetter.limitTorque(double value) = RSGetterLimitTorque;
  factory RSGetter.curKp(double value) = RSGetterCurKp;
  factory RSGetter.curKi(double value) = RSGetterCurKi;
  factory RSGetter.curFiltGain(double value) = RSGetterCurFiltGain;
  factory RSGetter.locRef(double value) = RSGetterLocRef;
  factory RSGetter.limitSpd(double value) = RSGetterLimitSpd;
  factory RSGetter.limitCur(double value) = RSGetterLimitCur;
  factory RSGetter.mechPos(double value) = RSGetterMechPos;
  factory RSGetter.iqf(double value) = RSGetterIqf;
  factory RSGetter.mechVel(double value) = RSGetterMechVel;
  factory RSGetter.vbus(double value) = RSGetterVbus;
  factory RSGetter.locKp(double value) = RSGetterLocKp;
  factory RSGetter.spdKp(double value) = RSGetterSpdKp;
  factory RSGetter.spdKi(double value) = RSGetterSpdKi;
  factory RSGetter.spdFiltGain(double value) = RSGetterSpdFiltGain;
  factory RSGetter.accRad(double value) = RSGetterAccRad;
  factory RSGetter.velMax(double value) = RSGetterVelMax;
  factory RSGetter.accSet(double value) = RSGetterAccSet;
  factory RSGetter.epscanTime(int value) = RSGetterEpscanTime;
  factory RSGetter.cantimeout(int value) = RSGetterCantimeout;
  factory RSGetter.zeroSta(bool value) = RSGetterZeroSta;

  factory RSGetter.fromByteData(ByteData data) =>
      switch (RSKey.fromByteData(data)) {
        .runMode => .runMode(RSRunMode.fromValue(data.getUint8(4))),
        .iqRef => .iqRef(data.getFloat32(4, .little)),
        .spdRef => .spdRef(data.getFloat32(4, .little)),
        .limitTorque => .limitTorque(data.getFloat32(4, .little)),
        .curKp => .curKp(data.getFloat32(4, .little)),
        .curKi => .curKi(data.getFloat32(4, .little)),
        .curFiltGain => .curFiltGain(data.getFloat32(4, .little)),
        .locRef => .locRef(data.getFloat32(4, .little)),
        .limitSpd => .limitSpd(data.getFloat32(4, .little)),
        .limitCur => .limitCur(data.getFloat32(4, .little)),
        .mechPos => .mechPos(data.getFloat32(4, .little)),
        .iqf => .iqf(data.getFloat32(4, .little)),
        .mechVel => .mechVel(data.getFloat32(4, .little)),
        .vbus => .vbus(data.getFloat32(4, .little)),
        .locKp => .locKp(data.getFloat32(4, .little)),
        .spdKp => .spdKp(data.getFloat32(4, .little)),
        .spdKi => .spdKi(data.getFloat32(4, .little)),
        .spdFiltGain => .spdFiltGain(data.getFloat32(4, .little)),
        .accRad => .accRad(data.getFloat32(4, .little)),
        .velMax => .velMax(data.getFloat32(4, .little)),
        .accSet => .accSet(data.getFloat32(4, .little)),
        .epscanTime => .epscanTime(5 * (data.getUint16(4, .little) - 1) + 10),
        .cantimeout => .cantimeout(50 * data.getUint32(4, .little)),
        .zeroSta => .zeroSta(data.getUint8(4) != 0),
      };
}

@freezed
sealed class RSSetter with _$RSSetter {
  const RSSetter._();

  factory RSSetter.runMode(RSRunMode value) = RSSetterRunMode;
  factory RSSetter.iqRef(double value) = RSSetterIqRef;
  factory RSSetter.spdRef(double value) = RSSetterSpdRef;
  factory RSSetter.limitTorque(double value) = RSSetterLimitTorque;
  factory RSSetter.curKp(double value) = RSSetterCurKp;
  factory RSSetter.curKi(double value) = RSSetterCurKi;
  factory RSSetter.curFiltGain(double value) = RSSetterCurFiltGain;
  factory RSSetter.locRef(double value) = RSSetterLocRef;
  factory RSSetter.limitSpd(double value) = RSSetterLimitSpd;
  factory RSSetter.limitCur(double value) = RSSetterLimitCur;
  factory RSSetter.locKp(double value) = RSSetterLocKp;
  factory RSSetter.spdKp(double value) = RSSetterSpdKp;
  factory RSSetter.spdKi(double value) = RSSetterSpdKi;
  factory RSSetter.spdFiltGain(double value) = RSSetterSpdFiltGain;
  factory RSSetter.accRad(double value) = RSSetterAccRad;
  factory RSSetter.velMax(double value) = RSSetterVelMax;
  factory RSSetter.accSet(double value) = RSSetterAccSet;

  /// [value] in milliseconds
  /// 落在区间 5(n-1) + 10 中
  factory RSSetter.epscanTime(int value) = RSSetterEpscanTime;

  /// [value] in microseconds
  /// 落在区间 50n 中
  factory RSSetter.cantimeout(int value) = RSSetterCantimeout;
  factory RSSetter.zeroSta(bool value) = RSSetterZeroSta;

  ByteData toByteData() => switch (this) {
    RSSetterRunMode(:final value) =>
      RSKey.runMode.toByteData()..setUint8(4, value.value),
    RSSetterIqRef(:final value) =>
      RSKey.iqRef.toByteData()..setFloat32(4, value, .little),
    RSSetterSpdRef(:final value) =>
      RSKey.spdRef.toByteData()..setFloat32(4, value, .little),
    RSSetterLimitTorque(:final value) =>
      RSKey.limitTorque.toByteData()..setFloat32(4, value, .little),
    RSSetterCurKp(:final value) =>
      RSKey.curKp.toByteData()..setFloat32(4, value, .little),
    RSSetterCurKi(:final value) =>
      RSKey.curKi.toByteData()..setFloat32(4, value, .little),
    RSSetterCurFiltGain(:final value) =>
      RSKey.curFiltGain.toByteData()..setFloat32(4, value, .little),
    RSSetterLocRef(:final value) =>
      RSKey.locRef.toByteData()..setFloat32(4, value, .little),
    RSSetterLimitSpd(:final value) =>
      RSKey.limitSpd.toByteData()..setFloat32(4, value, .little),
    RSSetterLimitCur(:final value) =>
      RSKey.limitCur.toByteData()..setFloat32(4, value, .little),
    RSSetterLocKp(:final value) =>
      RSKey.locKp.toByteData()..setFloat32(4, value, .little),
    RSSetterSpdKp(:final value) =>
      RSKey.spdKp.toByteData()..setFloat32(4, value, .little),
    RSSetterSpdKi(:final value) =>
      RSKey.spdKi.toByteData()..setFloat32(4, value, .little),
    RSSetterSpdFiltGain(:final value) =>
      RSKey.spdFiltGain.toByteData()..setFloat32(4, value, .little),
    RSSetterAccRad(:final value) =>
      RSKey.accRad.toByteData()..setFloat32(4, value, .little),
    RSSetterVelMax(:final value) =>
      RSKey.velMax.toByteData()..setFloat32(4, value, .little),
    RSSetterAccSet(:final value) =>
      RSKey.accSet.toByteData()..setFloat32(4, value, .little),
    RSSetterEpscanTime(:final value) =>
      RSKey.epscanTime.toByteData()
        ..setUint16(4, ((value - 10) / 5).round() + 1, .little),
    RSSetterCantimeout(:final value) =>
      RSKey.cantimeout.toByteData()
        ..setUint32(4, (value / 50).round(), .little),
    RSSetterZeroSta(:final value) =>
      RSKey.zeroSta.toByteData()..setUint8(4, value ? 1 : 0),
  };
}
