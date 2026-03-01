import 'dart:async';
import 'dart:io';

import 'package:han_dog/han_dog.dart';
import 'package:frequency_watch/frequency_watch.dart';

/// 遥控器测试脚本
/// 用法：dart run example/test_controller.dart
void main() async {
  RealFrequency.manager.watch();

  final controller = RealController('/dev/yunzhuo');
  if (!controller.open()) {
    print('Failed to open /dev/yunzhuo');
    exit(1);
  }
  print('Controller opened. Waiting for data...\n');

  // 标零标志位
  bool calibrateFlag = false;
  controller.calibrate.listen((_) {
    calibrateFlag = true;
  });

  // 每秒打印完整信息
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('');
  });

  int frame = 0;
  controller.stateStream.listen((state) {
    frame++;
    {
      final ch = state.rawChannels;
      print('=== frame $frame | Hz: ${controller.hz.value} | calibrate: $calibrateFlag ===');
      print('CH1-CH8:   ${_fmt(ch, 0, 8)}');
      print('CH9-CH16:  ${_fmt(ch, 8, 16)}');
      print('Parsed: $state');
      if (calibrateFlag) {
        print('*** CALIBRATE WAS TRIGGERED ***');
        calibrateFlag = false;
      }
    }
  });

  // Ctrl+C 退出
  ProcessSignal.sigint.watch().listen((_) {
    print('\nExiting...');
    controller.dispose();
    exit(0);
  });
}

String _fmt(List<int> ch, int from, int to) {
  final buf = StringBuffer();
  for (int i = from; i < to; i++) {
    buf.write('[$i]=${ch[i].toString().padLeft(4)}  ');
  }
  return buf.toString();
}
