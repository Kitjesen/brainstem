import 'package:test/test.dart';

import '../bin/read_controller.dart' show parseOptions;

void main() {
  test(
    'receiver probe defaults to the stable short name and bounded duration',
    () {
      expect(parseOptions([]), (port: '/dev/yunzhuo', seconds: 5));
      expect(parseOptions(['/dev/test', '60']), (
        port: '/dev/test',
        seconds: 60,
      ));
    },
  );
  test('rejects invalid arguments before any hardware is constructed', () {
    for (final args in <List<String>>[
      ['', '5'],
      ['/dev/test', '0'],
      ['/dev/test', '-1'],
      ['/dev/test', '61'],
      ['/dev/test', 'bad'],
      ['a', '1', 'extra'],
    ]) {
      expect(() => parseOptions(args), throwsFormatException);
    }
  });
}
