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
        127,
        torque: 110.0,
        position: 12,
        velocity: 14,
        kp: 4500,
        kd: 80,
      ),
      _yourcee(('41540faaa3fc08fa31f777e666cccc0d0a')),
    );
    check(
      2,
      RSEvent.control(
        127,
        torque: 3.0,
        position: 1.0,
        velocity: 2.0,
        kp: 600.0,
        kd: 5.0,
      ),
      _yourcee(('41540c199bfc088a2e91111eb80ccd0d0a')),
    );
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
      data2: 0x7f,
      canId: 0xfd,
      data1: _b([0x99, 0x7a, 0x7f, 0xd7, 0x7f, 0xff, 0x01, 0x22]),
    ),
    isA<RSStateReport>()
        .having((e) => e.canId, 'canId', 0x7f)
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
      data2: 0x7f,
      canId: 0xfd,
      data1: _b([0x99, 0x7a, 0x7f, 0xd7, 0x7f, 0xff, 0x01, 0x22]),
    ),
    isA<RSStateResponse>()
        .having((e) => e.canId, 'canId', 0x7f)
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
