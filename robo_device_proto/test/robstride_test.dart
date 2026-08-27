import 'dart:typed_data';

import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:robo_device_proto/src/robostride/internal.dart';
import 'package:test/test.dart';
import 'package:meta/meta.dart';

void main() {
  check(
    'run mode',
    RSEvent.set(4, hostId: 255, setter: .runMode(.velocity)),
    'ext: 1200ff04 |08| 05 70 00 00 02 00 00 00',
  );

  group('set reporting', () {
    check(
      false,
      RSEvent.setReporting(1, hostId: 0xfd, enable: false),
      _yourcee('4154c007e80c0801020304050600000d0a'),
    );
    check(
      true,
      RSEvent.setReporting(1, hostId: 0xfd, enable: true),
      _yourcee('4154c007e80c0801020304050601000d0a'),
    );
  });

  group('control', () {
    check(
      1,
      RSEvent.control(
        1,
        torque: 110.0,
        position: 12,
        velocity: 14,
        kp: 4500,
        kd: 80,
      ),
      _yourcee(('41540faaa00808fa31f777e666cccc0d0a')),
    );
    check(
      2,
      RSEvent.control(
        2,
        torque: 3.0,
        position: 1.0,
        velocity: 2.0,
        kp: 600.0,
        kd: 5.0,
      ),
      _yourcee(('41540c199810088a2e91111eb80ccd0d0a')),
    );

    test('CAN IDs 1-3 encode with RS04 ranges', () {
      final frame = RSEvent.control(
        1,
        torque: 10.0,
        velocity: 10.0,
        kp: 100.0,
        kd: 1.0,
      ).toDataFrame();

      expect(
        frame.data2,
        floatToUint16(
          10.0,
          -rs04MotorLimits.torqueMax,
          rs04MotorLimits.torqueMax,
        ),
      );
      expect(
        frame.bytes.getUint16(2),
        floatToUint16(
          10.0,
          -rs04MotorLimits.velocityMax,
          rs04MotorLimits.velocityMax,
        ),
      );
      expect(
        frame.bytes.getUint16(4),
        floatToUint16(100.0, 0.0, rs04MotorLimits.kpMax),
      );
      expect(
        frame.bytes.getUint16(6),
        floatToUint16(1.0, 0.0, rs04MotorLimits.kdMax),
      );
    });

    test('CAN ID 4 encodes with RS02 ranges', () {
      final frame = RSEvent.control(
        4,
        torque: 10.0,
        velocity: 10.0,
        kp: 100.0,
        kd: 1.0,
      ).toDataFrame();

      expect(
        frame.data2,
        floatToUint16(
          10.0,
          -rs02MotorLimits.torqueMax,
          rs02MotorLimits.torqueMax,
        ),
      );
      expect(
        frame.bytes.getUint16(2),
        floatToUint16(
          10.0,
          -rs02MotorLimits.velocityMax,
          rs02MotorLimits.velocityMax,
        ),
      );
      expect(
        frame.bytes.getUint16(4),
        floatToUint16(100.0, 0.0, rs02MotorLimits.kpMax),
      );
      expect(
        frame.bytes.getUint16(6),
        floatToUint16(1.0, 0.0, rs02MotorLimits.kdMax),
      );
    });
  });

  group('Han Dog motor layout', () {
    test('CAN IDs map explicitly to the installed hardware', () {
      expect(hanDogMotorLayout.keys, orderedEquals([1, 2, 3, 4]));
      expect(rsMotorSlotForCanId(1).role, HanDogMotorRole.hip);
      expect(rsMotorSlotForCanId(1).model, RSMotorModel.rs04);
      expect(rsMotorSlotForCanId(2).role, HanDogMotorRole.thigh);
      expect(rsMotorSlotForCanId(2).model, RSMotorModel.rs04);
      expect(rsMotorSlotForCanId(3).role, HanDogMotorRole.calf);
      expect(rsMotorSlotForCanId(3).model, RSMotorModel.rs04);
      expect(rsMotorSlotForCanId(4).role, HanDogMotorRole.wheel);
      expect(rsMotorSlotForCanId(4).model, RSMotorModel.rs02);
      expect(validateHanDogMotorLayout, returnsNormally);
    });

    test('unknown CAN IDs fail instead of silently using RS04', () {
      expect(() => rsMotorLimitsForCanId(0), throwsArgumentError);
      expect(() => rsMotorLimitsForCanId(5), throwsArgumentError);
    });

    test('startup summary is generated from the same source of truth', () {
      expect(hanDogMotorCodecSummary, contains('CAN1 hip=RS04'));
      expect(hanDogMotorCodecSummary, contains('CAN4 wheel=RS02'));
      expect(hanDogMotorCodecSummary, contains('v=±44'));
      expect(hanDogMotorCodecSummary, contains('t=±17'));
    });

    test('documents the RS02/RS04 velocity scaling mismatch', () {
      final rs04EncodedTen = floatToUint16(
        10.0,
        -rs04MotorLimits.velocityMax,
        rs04MotorLimits.velocityMax,
      );
      final rs02Interpretation = uint16ToFloat(
        rs04EncodedTen,
        -rs02MotorLimits.velocityMax,
        rs02MotorLimits.velocityMax,
      );
      expect(rs02Interpretation, closeTo(10.0 * 44.0 / 15.0, 0.002));

      final rs02EncodedTen = floatToUint16(
        10.0,
        -rs02MotorLimits.velocityMax,
        rs02MotorLimits.velocityMax,
      );
      final rs04DecodedFeedback = uint16ToFloat(
        rs02EncodedTen,
        -rs04MotorLimits.velocityMax,
        rs04MotorLimits.velocityMax,
      );
      expect(rs04DecodedFeedback, closeTo(10.0 * 15.0 / 44.0, 0.002));
    });
  });

  group('mixed motor feedback decoding', () {
    for (final entry in [(1, rs04MotorLimits), (4, rs02MotorLimits)]) {
      final canId = entry.$1;
      final limits = entry.$2;

      test('CAN ID $canId uses the matching physical ranges', () {
        final bytes = ByteData(8)
          ..setUint16(0, floatToUint16(0.5, -positionMax, positionMax))
          ..setUint16(
            2,
            floatToUint16(5.0, -limits.velocityMax, limits.velocityMax),
          )
          ..setUint16(
            4,
            floatToUint16(2.0, -limits.torqueMax, limits.torqueMax),
          )
          ..setUint16(6, 260);
        final state =
            RSState.fromDataFrame(
                  RSDataFrame(
                    mode: 0x18,
                    data2: canId,
                    canId: 0xfd,
                    data1: bytes.buffer.asUint8List(),
                  ),
                )
                as RSStateReport;

        expect(state.canId, canId);
        expect(state.position, closeTo(0.5, 0.001));
        expect(state.velocity, closeTo(5.0, 0.002));
        expect(state.torque, closeTo(2.0, 0.005));
        expect(state.temperature, 26.0);
      });
    }
  });

  check(
    'request locKp',
    RSEvent.get(0x7f, hostId: 0xfd, key: .locKp),
    RSDataFrame(
      mode: 0x11,
      data2: 0xfd,
      canId: 0x7f,
      data1: _b([0x1e, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
    ),
  );
  check(
    'response locKp',
    RSState.getter(hostId: 0xfd, canId: 0x7f, getter: RSGetter.locKp(30.0)),
    RSDataFrame(
      mode: 0x11,
      data2: 0x7f,
      canId: 0xfd,
      data1: _b([0x1e, 0x70, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x41]),
    ),
  );

  check(
    'report',
    RSDataFrame(
      mode: 24,
      data2: 0x01,
      canId: 0xfd,
      data1: _b([0x99, 0x7a, 0x7f, 0xd7, 0x7f, 0xff, 0x01, 0x22]),
    ),
    isA<RSStateReport>()
        .having((e) => e.canId, 'canId', 0x01)
        .having((e) => e.hostId, 'hostId', 0xfd)
        .having((e) => e.position, 'position', closeTo(2.5, 0.01))
        .having((e) => e.velocity, 'velocity', closeTo(0.0, 0.05))
        .having((e) => e.torque, 'torque', closeTo(0.0, 0.05))
        .having((e) => e.temperature, 'temperature', closeTo(29.0, 0.05))
        .having((e) => e.errors, 'errors', 0),
  );

  check(
    'motion control ACK (mode 0x01)',
    RSDataFrame(
      mode: 0x01,
      data2: 0x01,
      canId: 0xfd,
      data1: _b([0x99, 0x7a, 0x7f, 0xd7, 0x7f, 0xff, 0x01, 0x22]),
    ),
    isA<RSStateResponse>()
        .having((e) => e.canId, 'canId', 0x01)
        .having((e) => e.hostId, 'hostId', 0xfd)
        .having((e) => e.position, 'position', closeTo(2.5, 0.01))
        .having((e) => e.velocity, 'velocity', closeTo(0.0, 0.05))
        .having((e) => e.torque, 'torque', closeTo(0.0, 0.05))
        .having((e) => e.temperature, 'temperature', closeTo(29.0, 0.05))
        .having((e) => e.errors, 'errors', 0),
  );
}

@isTest
void check(Object? description, Object actual, Object matcher) {
  test(description, () {
    switch ((actual, matcher)) {
      case (RSEvent a, String b):
        expect(a.toCanFrame().toString(), b);
      case (RSEvent a, RSDataFrame b):
        expect(a.toDataFrame(), b);
      case (RSState a, RSDataFrame b):
        expect(a, RSState.fromDataFrame(b));
      case (RSDataFrame a, TypeMatcher<RSState> b):
        expect(RSState.fromDataFrame(a), b);
      default:
        throw UnimplementedError();
    }
  });
}

/// Yourcee 格式的 can 帧
/// 4154_c007e80c_08_0102030405060000_0d0a
String _yourcee(String uiString) {
  // extract xxx from 4154xxx0d0a
  final start = uiString.indexOf('4154') + 4;
  final end = uiString.indexOf('0d0a');
  final hexString = uiString.substring(start, end);

  // 前面四个字节代表 id, 需要右移3位
  final id = int.parse(hexString.substring(0, 8), radix: 16) >> 3;
  final length = int.parse(hexString.substring(8, 10), radix: 16);
  final data = _strB(hexString.substring(10));
  return 'ext: ${_bInt(id)} |${_bInt(length, 2)}| ${_bStr(data)}';
}

String _bStr(Uint8List data) =>
    data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
String _bInt(int value, [int width = 8]) =>
    value.toRadixString(16).padLeft(width, '0');
Uint8List _strB(String hexString) => .fromList(
  .generate(
    hexString.length ~/ 2,
    (i) => int.parse(hexString.substring(i * 2, i * 2 + 2), radix: 16),
  ).toList(),
);
Uint8List _b(List<int> list) => .fromList(list);
