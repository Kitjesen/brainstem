import 'dart:isolate';
import 'package:test/test.dart';
import 'package:serial_port/serial_port.dart';

Future<void> _justDispose((SendPort, Null) message) async {
  final port = SerialPort();
  port.dispose();
  message.$1.send(null);
}

Future<void> _openFailed((SendPort, String) message) async {
  final port = SerialPort()..init(message.$2);
  assert(port.open() == false);
  port.dispose();
  message.$1.send(null);
}

Future<void> _openSuccess((SendPort, String) message) async {
  final port = SerialPort()..init(message.$2);
  assert(port.open() == true);
  port.dispose();
  message.$1.send(null);
}

Future<void> _openSuccessWithClose((SendPort, String) message) async {
  final port = SerialPort()..init(message.$2);
  assert(port.open() == true);
  port.close();
  port.dispose();
  message.$1.send(null);
}

void main() {
  t('just dispose', _justDispose, null);
  t('open failed', _openFailed, 'xxx');
  t('open success', _openSuccess, '/dev/ttyACM0');
  t('open success', _openSuccess, '/dev/ttyUSB0');
  t('open success with close', _openSuccessWithClose, '/dev/ttyACM0');
}

void t<T>(
  Object description,
  void Function((SendPort, T)) entryPoint,
  T message,
) {
  test(description, () async {
    await checkTerminate<T>(entryPoint, message);
  });
}

Future<void> checkTerminate<T>(
  void Function((SendPort, T)) entryPoint,
  T message,
) async {
  final onExit = ReceivePort(); // Isolate 真正退出时会触发
  final notify = ReceivePort(); // 业务逻辑跑完时主动发的通知

  Isolate? iso;
  try {
    iso = await Isolate.spawn(
      entryPoint,
      (notify.sendPort, message),
      onExit: onExit.sendPort,
      errorsAreFatal: true,
    );

    // 1) 先等业务逻辑结束（确保已调用 uninitialize）
    await notify.first.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw TestFailure('function did not complete'),
    );

    // 2) 再等 Isolate 实际退出（如果有遗留 Timer/资源，它不会退出）
    await onExit.first.timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw TestFailure('isolate did not exit'),
    );
  } finally {
    // 清理（即使失败也确保不遗留子进程）
    notify.close();
    onExit.close();
    iso?.kill(priority: Isolate.immediate);
  }
}
