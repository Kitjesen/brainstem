/// 原始 ping 工具 — 对照验证
/// 直接在 4 路 PCAN 通道上扫描 canId 0~254，打印所有响应
library;
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

void main() async {
  final channels = {
    'can0 (usbbus1/FL)': PcanChannel.usbbus1,
    'can1 (usbbus2/RL)': PcanChannel.usbbus2,
    'can2 (usbbus3/FR)': PcanChannel.usbbus3,
    'can3 (usbbus4/RR)': PcanChannel.usbbus4,
  };

  final controllers = <String, PcanController<RSEvent, RSState>>{};

  print('=== 原始 4 路 CAN 全扫描 (canId 0~254) ===\n');

  for (final entry in channels.entries) {
    final pcan = PcanController<RSEvent, RSState>(entry.value);
    if (pcan.open()) {
      controllers[entry.key] = pcan;
      print('  ${entry.key}: ✓ 已打开');
    } else {
      print('  ${entry.key}: ✗ 打开失败');
    }
  }

  print('');

  // 监听所有响应
  for (final entry in controllers.entries) {
    entry.value.state.listen((state) {
      print('  [${entry.key}] $state');
    });
  }

  // 发送 getDeviceId 到 canId 1~4（和 ping.dart 一致）
  print('发送 ping (canId 1~4) ...');
  for (final pcan in controllers.values) {
    for (int i = 1; i <= 4; i++) {
      pcan.add(RSEvent.getDeviceId(i));
    }
  }

  // 等待响应
  await Future<void>.delayed(const Duration(seconds: 3));

  print('\n扫描完成');

  // 清理
  for (final pcan in controllers.values) {
    pcan.dispose();
  }
}
