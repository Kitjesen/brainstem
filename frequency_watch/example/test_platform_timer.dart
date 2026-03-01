import 'dart:async';

import 'package:frequency_watch/frequency_watch.dart';

void main() {
  final watcher = FrequencyWatch(windowSize: 100);
  int tick = 0;

  // 模拟 1000Hz 的定时器
  const duration = Duration(milliseconds: 1);

  Timer.periodic(duration, (timer) {
    watcher.watch();
    tick++;

    if (tick % 100 == 0) {
      print(watcher);
    }

    if (tick >= 500) {
      timer.cancel();
      print("Finished.");
    }
  });
}
