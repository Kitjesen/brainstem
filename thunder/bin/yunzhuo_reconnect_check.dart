import 'dart:async';
import 'dart:io';
import 'package:thunder/src/real_controller.dart';

// Uses a pseudo terminal only; never creates motor or CAN objects.
Future<void> main(List<String> args) async {
  final controller = RealController(args.single);
  var frames = 0;
  final first = Completer<void>();
  final restored = Completer<void>();
  var reopened = false;
  final sub = controller.stateStream.listen((state) {
    frames++;
    if (!first.isCompleted) first.complete();
    if (reopened && !restored.isCompleted) restored.complete();
  }, onError: (Object error, StackTrace stack) {
    stderr.writeln('$error\n$stack');
  });
  try {
    if (!controller.open()) throw StateError('Cannot open test PTY');
    stdout.writeln('READY');
    await first.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!await controller.reopen().timeout(const Duration(seconds: 3))) {
      throw StateError('Reopen failed');
    }
    reopened = true;
    stdout.writeln('REOPENED');
    await restored.future.timeout(const Duration(seconds: 5));
    stdout.writeln('PASS: feedback resumed, frames=$frames');
  } finally {
    await sub.cancel();
    controller.dispose();
  }
  exit(0);
}
