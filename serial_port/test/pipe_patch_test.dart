import 'dart:io';

import 'package:test/test.dart';

import '../hook/build.dart' show applyPipeLeakPatch;

void main() {
  test('deployed pipe leak patch applies once and is idempotent', () async {
    final package = Directory('serial_port').existsSync()
        ? Directory('serial_port').absolute
        : Directory.current.absolute;
    final upstream = await Process.run('git', [
      'show',
      'HEAD:src/SerialPortUnixBase.cpp',
    ], workingDirectory: '${package.path}/src/CSerialPort');
    expect(upstream.exitCode, 0);
    final temp = await Directory.systemTemp.createTemp('serial-pipe-patch-');
    try {
      final file = File('${temp.path}/src/SerialPortUnixBase.cpp');
      await file.parent.create(recursive: true);
      await file.writeAsString(upstream.stdout as String);
      await applyPipeLeakPatch(package.uri, temp);
      final once = await file.readAsString();
      expect(once, contains('m_pipefd[0] = -1;'));
      expect(once, contains('close(m_pipefd[0]);'));
      expect(once, contains('close(m_pipefd[1]);'));
      await applyPipeLeakPatch(package.uri, temp);
      expect(await file.readAsString(), once);
      await file.writeAsString('unexpected upstream content');
      await expectLater(
        applyPipeLeakPatch(package.uri, temp),
        throwsStateError,
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
