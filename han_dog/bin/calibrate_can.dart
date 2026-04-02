/// CAN 通道 ↔ 腿映射校准工具。
///
/// 打开全部 4 路 CAN，实时监听关节位置变化。
/// 手动转动某条腿的电机，工具显示是哪个 CAN 通道 + 哪个 motor ID 报告了变化。
/// 用于确认 usbbus1/2/3/4 和 FR/FL/RR/RL 的实际对应关系。
///
/// 用法: dart run han_dog/bin/calibrate_can.dart
///
/// 步骤:
///   1. 启动后等待 "Ready" 提示
///   2. 用手转动 FR 腿的某个关节（如大腿），观察输出
///   3. 记录显示的 CAN 通道（can0/can1/can2/can3）
///   4. 对 FL、RR、RL 重复
///   5. 根据结果修改 han_dog.dart 中的 RealJoint 通道映射
library;

import 'dart:async';
import 'dart:io';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

const _channelNames = {
  PcanChannel.usbbus1: 'can0 (usbbus1)',
  PcanChannel.usbbus2: 'can1 (usbbus2)',
  PcanChannel.usbbus3: 'can2 (usbbus3)',
  PcanChannel.usbbus4: 'can3 (usbbus4)',
};

const _motorNames = {1: 'Hip', 2: 'Thigh', 3: 'Calf', 4: 'Foot'};

void main() async {
  print('''
╔═══════════════════════════════════════════════════╗
║       CAN 通道 ↔ 腿映射校准工具                  ║
╠═══════════════════════════════════════════════════╣
║  手动转动机器人的关节，观察哪个 CAN 通道响应。    ║
║  用于确认 usbbus1-4 和 FR/FL/RR/RL 的对应关系。  ║
║                                                   ║
║  Ctrl+C 退出                                      ║
╚═══════════════════════════════════════════════════╝
''');

  // 打开 4 路 CAN
  final channels = [
    PcanChannel.usbbus1,
    PcanChannel.usbbus2,
    PcanChannel.usbbus3,
    PcanChannel.usbbus4,
  ];
  final pcans = <PcanChannel, PcanController<RSEvent, RSState>>{};
  final subs = <StreamSubscription<RSState>>[];

  for (final ch in channels) {
    final pcan = PcanController<RSEvent, RSState>(ch);
    if (!pcan.open()) {
      print('  ${_channelNames[ch]} ✗ 打开失败');
      continue;
    }
    print('  ${_channelNames[ch]} ✓');
    pcans[ch] = pcan;
  }

  if (pcans.isEmpty) {
    print('\n[错误] 没有可用的 CAN 通道');
    exit(1);
  }

  // 启用上报
  print('\n启用电机主动上报...');
  for (final pcan in pcans.values) {
    for (int retry = 0; retry < 3; retry++) {
      for (int id = 1; id <= 4; id++) {
        pcan.add(RSEvent.setReporting(id, enable: true));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  await Future<void>.delayed(const Duration(seconds: 1));

  // 记录每个通道每个电机的基准位置
  final baseline = <String, double>{};
  final lastReport = <String, double>{};

  for (final entry in pcans.entries) {
    final ch = entry.key;
    final pcan = entry.value;
    subs.add(pcan.state.listen((state) {
      if (state is RSStateReport) {
        final key = '${_channelNames[ch]}:${state.canId}';
        final pos = state.position;

        // 首次记录基准位置
        baseline.putIfAbsent(key, () => pos);
        lastReport[key] = pos;

        // 位置变化超过 0.05 rad (~3°) 才报告
        final delta = (pos - baseline[key]!).abs();
        if (delta > 0.05) {
          final motor = _motorNames[state.canId] ?? 'Motor${state.canId}';
          final degDelta = (delta * 180 / 3.14159).toStringAsFixed(1);
          print(
            '  ▶ ${_channelNames[ch]}  '
            'Motor $motor (ID ${state.canId})  '
            'Δ$degDelta°  '
            'pos=${pos.toStringAsFixed(3)} rad',
          );
          // 更新基准，避免持续刷屏
          baseline[key] = pos;
        }
      }
    }));
  }

  print('''

╔═══════════════════════════════════════════════════╗
║  Ready! 现在手动转动机器人的关节:                 ║
║                                                   ║
║  1. 转动 FR (前右) 某个关节 → 记录 CAN 通道      ║
║  2. 转动 FL (前左) 某个关节 → 记录 CAN 通道      ║
║  3. 转动 RR (后右) 某个关节 → 记录 CAN 通道      ║
║  4. 转动 RL (后左) 某个关节 → 记录 CAN 通道      ║
║                                                   ║
║  变化超过 3° 的关节会显示在下面:                   ║
╚═══════════════════════════════════════════════════╝
''');

  // 每 5 秒打印一次汇总
  Timer.periodic(const Duration(seconds: 10), (_) {
    if (lastReport.isEmpty) return;
    print('\n── 当前各通道电机位置 ──');
    for (final ch in channels) {
      if (!pcans.containsKey(ch)) continue;
      final positions = <String>[];
      for (int id = 1; id <= 4; id++) {
        final key = '${_channelNames[ch]}:$id';
        final pos = lastReport[key];
        if (pos != null) {
          positions.add('${_motorNames[id]}=${pos.toStringAsFixed(2)}');
        }
      }
      if (positions.isNotEmpty) {
        print('  ${_channelNames[ch]}: ${positions.join(', ')}');
      }
    }
    print('');
  });

  // Ctrl+C 清理
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n清理中...');
    for (final sub in subs) {
      await sub.cancel();
    }
    for (final pcan in pcans.values) {
      pcan.close();
      pcan.dispose();
    }
    print('已退出');
    exit(0);
  });

  // 保持运行
  await Completer<void>().future;
}
