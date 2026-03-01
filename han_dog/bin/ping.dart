import 'dart:async';
import 'dart:io';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

/// 四条腿的 PCAN 通道映射（与 han_dog.dart 保持一致）
const _legConfig = {
  'FR': PcanChannel.usbbus3,
  'FL': PcanChannel.usbbus1,
  'RR': PcanChannel.usbbus4,
  'RL': PcanChannel.usbbus2,
};

/// 每条腿的电机数量（canId 1~4）
const _motorsPerLeg = 4;

/// 默认超时时间
const _defaultTimeout = Duration(seconds: 3);

void main(List<String> args) async {
  final timeout = _parseTimeout(args);

  print('');
  print('╔══════════════════════════════════════╗');
  print('║       HAN DOG 电机连接诊断工具       ║');
  print('╚══════════════════════════════════════╝');
  print('');

  // 记录发现的电机: { "FR-1": mcuId, ... }
  final found = <String, BigInt>{};
  final pcans = <String, PcanController<RSEvent, RSState>>{};
  final subscriptions = <StreamSubscription<Object?>>[];

  // ── 1. 打开所有 PCAN 通道 ──
  print('[1/3] 打开 PCAN 通道...');
  final failedLegs = <String>[];

  for (final entry in _legConfig.entries) {
    final name = entry.key;
    final channel = entry.value;
    final pcan = PcanController<RSEvent, RSState>(channel);

    if (pcan.open()) {
      pcans[name] = pcan;
      print('  $name (${channel.name}) ✓');
    } else {
      failedLegs.add(name);
      print('  $name (${channel.name}) ✗ 打开失败');
    }
  }

  if (pcans.isEmpty) {
    print('');
    print('[错误] 所有 PCAN 通道打开失败，请检查:');
    print('  1. PCAN USB 设备是否已连接');
    print('  2. peak_usb 内核模块是否已加载: lsmod | grep peak');
    print('  3. CAN 接口是否已启动: sudo tools/setup_can.sh');
    exit(1);
  }

  // ── 2. 监听响应 & 发送 ping ──
  print('');
  print('[2/3] 发送 ping 请求 (超时 ${timeout.inSeconds}s)...');

  for (final entry in pcans.entries) {
    final legName = entry.key;
    final pcan = entry.value;

    // 监听 deviceId 响应
    subscriptions.add(pcan.state.listen((state) {
      if (state is RSStateDeviceId) {
        final key = '$legName-${state.canId}';
        found[key] = state.mcuId;
      }
    }));

    // 对 canId 1~4 发送 getDeviceId
    for (int id = 1; id <= _motorsPerLeg; id++) {
      pcan.add(RSEvent.getDeviceId(id));
    }
  }

  // 等待响应（提前退出优化：全部发现就不用等了）
  final expected = pcans.keys.length * _motorsPerLeg;
  final stopwatch = Stopwatch()..start();

  while (stopwatch.elapsed < timeout && found.length < expected) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  stopwatch.stop();

  // ── 3. 输出结果 ──
  print('');
  print('[3/3] 扫描结果 (耗时 ${stopwatch.elapsedMilliseconds}ms):');
  print('');
  _printResults(found, failedLegs);

  // ── 4. 主动上报测试 ──
  print('[4/4] 测试主动上报...');
  print('');

  // 记录每个关节收到的上报帧数
  final reportCount = <String, int>{};
  final reportSubs = <StreamSubscription<Object?>>[];

  // 监听上报帧
  for (final entry in pcans.entries) {
    final legName = entry.key;
    final pcan = entry.value;
    reportSubs.add(pcan.state.listen((state) {
      if (state is RSStateReport) {
        final key = '$legName-${state.canId}';
        reportCount[key] = (reportCount[key] ?? 0) + 1;
      }
    }));
  }

  // 发送 setReporting(enable: true)，每个电机发 3 次以确保送达
  for (var retry = 0; retry < 3; retry++) {
    for (final pcan in pcans.values) {
      for (int id = 1; id <= _motorsPerLeg; id++) {
        pcan.add(RSEvent.setReporting(id, enable: true));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  print('  已发送 setReporting(enable: true) x3');
  print('  等待上报帧 (2s)...');
  await Future<void>.delayed(const Duration(seconds: 2));

  // 输出结果
  final legNames = ['FR', 'FL', 'RR', 'RL'];
  final jointNames = ['Hip', 'Thigh', 'Calf', 'Foot'];
  print('');
  print('  ${'关节'.padRight(12)}${'上报帧数'.padRight(10)}状态');
  print('  ${'─' * 40}');

  int reportOk = 0;
  int reportFail = 0;
  for (final leg in legNames) {
    for (int i = 0; i < _motorsPerLeg; i++) {
      final canId = i + 1;
      final key = '$leg-$canId';
      final count = reportCount[key] ?? 0;
      final ok = count > 0;
      if (ok) { reportOk++; } else { reportFail++; }
      print('  ${leg.padRight(4)}${jointNames[i].padRight(8)}'
          '${count.toString().padRight(10)}'
          '${ok ? "✓ 上报正常" : "✗ 未收到上报"}');
    }
  }
  print('  ${'─' * 40}');
  print('');
  if (reportFail == 0) {
    print('  ✓ 全部 ${reportOk + reportFail}/${reportOk + reportFail} 关节主动上报正常');
  } else {
    print('  ✗ $reportOk/${reportOk + reportFail} 关节上报正常, $reportFail 个未收到上报');
    print('  → 未收到上报的关节请检查: 电机固件/CAN线缆/尝试断电重新上电');
  }
  print('');

  // ── 5. 对未上报的关节进一步诊断 ──
  final failedJoints = <String>[];
  for (final leg in legNames) {
    for (int i = 0; i < _motorsPerLeg; i++) {
      final key = '$leg-${i + 1}';
      if ((reportCount[key] ?? 0) == 0 && pcans.containsKey(leg)) {
        failedJoints.add(key);
      }
    }
  }

  if (failedJoints.isNotEmpty) {
    print('[5/5] 对未上报关节进行参数诊断...');
    print('');

    // 收集 getter 响应
    final getterResults = <String, RSState>{};
    final diagSubs = <StreamSubscription<Object?>>[];
    for (final entry in pcans.entries) {
      final legName = entry.key;
      diagSubs.add(entry.value.state.listen((state) {
        if (state is RSStateGetter) {
          final key = '$legName-${state.canId}';
          getterResults[key] = state;
        }
      }));
    }

    for (final joint in failedJoints) {
      final parts = joint.split('-');
      final leg = parts[0];
      final canId = int.parse(parts[1]);
      final pcan = pcans[leg]!;
      final jName = jointNames[canId - 1];

      print('  ── $leg $jName (CAN ID $canId) ──');

      // 读 epscanTime (主动上报周期)
      getterResults.clear();
      pcan.add(RSEvent.get(canId, key: RSKey.epscanTime));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      var result = getterResults[joint];
      if (result is RSStateGetter && result.getter != null) {
        print('    epscanTime (上报周期): ${result.getter}');
      } else {
        print('    epscanTime: 未响应');
      }

      // 读 runMode
      getterResults.clear();
      pcan.add(RSEvent.get(canId, key: RSKey.runMode));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      result = getterResults[joint];
      if (result is RSStateGetter && result.getter != null) {
        print('    runMode (运行模式): ${result.getter}');
      } else {
        print('    runMode: 未响应');
      }

      // 读 mechPos
      getterResults.clear();
      pcan.add(RSEvent.get(canId, key: RSKey.mechPos));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      result = getterResults[joint];
      if (result is RSStateGetter && result.getter != null) {
        print('    mechPos (位置): ${result.getter}');
      } else {
        print('    mechPos: 未响应');
      }

      // 读 vbus
      getterResults.clear();
      pcan.add(RSEvent.get(canId, key: RSKey.vbus));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      result = getterResults[joint];
      if (result is RSStateGetter && result.getter != null) {
        print('    vbus (总线电压): ${result.getter}');
      } else {
        print('    vbus: 未响应');
      }

      print('');
    }

    print('  处理建议:');
    print('    1. 若 epscanTime 响应正常 → 电机固件可能不支持 mode 0x18 上报');
    print('    2. 若参数全部未响应 → CAN 只能单向通信，检查线缆/接头');
    print('    3. 尝试: 断电重新上电该电机，再跑一次 ping');
    print('');

    for (final sub in diagSubs) {
      await sub.cancel();
    }
  }

  // 关闭上报
  for (final pcan in pcans.values) {
    for (int id = 1; id <= _motorsPerLeg; id++) {
      pcan.add(RSEvent.setReporting(id, enable: false));
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));

  // ── 清理 ──
  for (final sub in reportSubs) {
    await sub.cancel();
  }
  for (final sub in subscriptions) {
    await sub.cancel();
  }
  for (final pcan in pcans.values) {
    pcan.dispose();
  }

  exit(found.length == _legConfig.length * _motorsPerLeg && reportFail == 0 ? 0 : 1);
}

void _printResults(Map<String, BigInt> found, List<String> failedLegs) {
  final legNames = ['FR', 'FL', 'RR', 'RL'];
  final jointNames = ['Hip', 'Thigh', 'Calf', 'Foot'];

  // 表头
  print('  ${'Leg'.padRight(6)}'
      '${'Motor'.padRight(8)}'
      '${'CAN ID'.padRight(10)}'
      '${'Status'.padRight(10)}'
      'MCU ID');
  print('  ${'─' * 56}');

  int totalOk = 0;
  int totalFail = 0;

  for (final leg in legNames) {
    for (int i = 0; i < _motorsPerLeg; i++) {
      final canId = i + 1;
      final key = '$leg-$canId';
      final isFailed = failedLegs.contains(leg);
      final isFound = found.containsKey(key);

      String status;
      String mcuId;

      if (isFailed) {
        status = 'PCAN ERR';
        mcuId = '-';
        totalFail++;
      } else if (isFound) {
        status = 'OK';
        mcuId = found[key].toString();
        totalOk++;
      } else {
        status = 'TIMEOUT';
        mcuId = '-';
        totalFail++;
      }

      final statusStr = isFound ? '  ✓ $status' : '  ✗ $status';

      print('  ${leg.padRight(6)}'
          '${jointNames[i].padRight(8)}'
          '${'$canId'.padRight(10)}'
          '${statusStr.padRight(10)}'
          '  $mcuId');
    }
  }

  final total = totalOk + totalFail;
  print('  ${'─' * 56}');
  print('');

  if (totalFail == 0) {
    print('  ✓ 全部 $total/$total 电机在线');
  } else {
    print('  ✗ $totalOk/$total 电机在线, $totalFail 个离线');
  }
  print('');
}

Duration _parseTimeout(List<String> args) {
  for (int i = 0; i < args.length - 1; i++) {
    if (args[i] == '--timeout') {
      final seconds = int.tryParse(args[i + 1]);
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
  }
  return _defaultTimeout;
}
