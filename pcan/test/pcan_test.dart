import 'dart:isolate';
import 'package:test/test.dart';
import 'package:pcan/pcan.dart';

/// 在独立 Isolate 中执行 open->close。
Future<void> _openCloseEntry((SendPort, PcanChannel) args) async {
  final notify = args.$1;
  final pcan = Pcan(args.$2);
  pcan.open(PcanBaudRate.baud1M);
  await Future.delayed(const Duration(milliseconds: 100));
  pcan.close();
  notify.send(null); // terminate signal
}

void main() {
  group('Pcan open & close should not leak timers/resources', () {
    test('when opened', () async {
      await testOpenCloseLeak(_openCloseEntry, PcanChannel.usbbus1);
    });

    test('when not opened', () async {
      await testOpenCloseLeak(_openCloseEntry, PcanChannel.usbbus16);
    });
  });
}

Future<void> testOpenCloseLeak<T>(
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
