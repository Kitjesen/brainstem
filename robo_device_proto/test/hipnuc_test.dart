import 'dart:typed_data';

import 'package:robo_device_proto/device_proto.dart';
import 'package:test/test.dart';

void main() {
  test('parse data', () {
    final example =
        '91 08 15 23 09 A2 C4 47 08 15 1C 00 CC E8 61 BE 9A 35 56 3E 65 EA 72 3F 31 D0 7C BD'
        ' '
        '75 DD C5 BB 6B D7 24 BC 89 88 FC 40 01 00 6A 41 AB 2A 70 C2 96 D4 50 41 ED 03 43 41 41 F4 F4 C2 CC CA'
        ' '
        'F8 BE 73 6A 19 BE F0 00 1C 3D 8D 37 5C 3F';
    final bytes = example
        .split(' ')
        .map((e) => int.parse(e, radix: 16))
        .toList();

    final state = Hi91State.fromBytes(.fromList(bytes));
    expect(
      state,
      isA<Hi91State>()
          .having((e) => e.status.value, 'status', 5384)
          .having((e) => e.temperature, 'temperature', 35)
          .having((e) => e.airPressure, 'airPressure', closeTo(100676, 0.1))
          .having((e) => e.timeStamp, 'timeStamp', 1840392)
          .having(
            (e) => e.acceleration.x,
            'acceleration.x',
            closeTo(-0.220615, 0.000001),
          )
          .having(
            (e) => e.acceleration.y,
            'acceleration.y',
            closeTo(0.209189, 0.000001),
          )
          .having(
            (e) => e.acceleration.z,
            'acceleration.z',
            closeTo(0.948889, 0.000001),
          )
          .having(
            (e) => e.gyroscope.x,
            'gyroscope.x',
            closeTo(-0.061722, 0.000001),
          )
          .having(
            (e) => e.gyroscope.y,
            'gyroscope.y',
            closeTo(-0.0060384, 0.000001),
          )
          .having(
            (e) => e.gyroscope.z,
            'gyroscope.z',
            closeTo(-0.0100611, 0.000001),
          )
          .having(
            (e) => e.magneticField.x,
            'magneticField.x',
            closeTo(7.89167, 0.00001),
          )
          .having(
            (e) => e.magneticField.y,
            'magneticField.y',
            closeTo(14.625, 0.001),
          )
          .having(
            (e) => e.magneticField.z,
            'magneticField.z',
            closeTo(-60.0417, 0.0001),
          )
          .having((e) => e.roll, 'roll', closeTo(13.0519, 0.0001))
          .having((e) => e.pitch, 'pitch', closeTo(12.1885, 0.0001))
          .having((e) => e.yaw, 'yaw', closeTo(-122.477, 0.001))
          .having(
            (e) => e.quaternion.w,
            'quaternion.w',
            closeTo(-0.485922, 0.000001),
          )
          .having(
            (e) => e.quaternion.x,
            'quaternion.x',
            closeTo(-0.14982, 0.00001),
          )
          .having(
            (e) => e.quaternion.y,
            'quaternion.y',
            closeTo(0.0380868, 0.0000001),
          )
          .having(
            (e) => e.quaternion.z,
            'quaternion.z',
            closeTo(0.860223, 0.000001),
          ),
    );
  });
}
