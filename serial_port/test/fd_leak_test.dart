import 'dart:io';

import 'package:serial_port/serial_port.dart';
import 'package:test/test.dart';

void main() {
  test('disposing SerialPort does not leak Unix wake-up pipes', () {
    if (!Platform.isLinux) return;

    int fdCount() => Directory('/proc/self/fd').listSync().length;

    final before = fdCount();
    for (var i = 0; i < 100; i++) {
      SerialPort().dispose();
    }
    final after = fdCount();

    expect(after, lessThanOrEqualTo(before + 4));
  });
}
