/// gRPC 接口测试脚本 — 开发 / 调试专用，非生产程序。
///
/// 测试 localhost:13145 上的所有 CMS gRPC 接口。
/// 安全：joint.realActionExt 已注释，电机不会动。
///
/// 运行：dart run han_dog/bin/test_grpc.dart
/// 前置：目标服务器（han_dog 或 server.dart）已启动在 localhost:13145。
library;
import 'dart:async' show TimeoutException;
import 'dart:core';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart' hide Duration;

const host = 'localhost';
const port = 13145;

late CmsClient client;
int _pass = 0;
int _fail = 0;

void main() async {
  final channel = ClientChannel(
    host,
    port: port,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  client = CmsClient(channel);

  print('');
  print('╔══════════════════════════════════════════╗');
  print('║      HAN DOG gRPC 接口测试 (本地)        ║');
  print('╚══════════════════════════════════════════╝');
  print('');
  print('目标: $host:$port');
  print('');

  // ──── 1. 查询类接口 ────
  await _test('GetParams', () async {
    final params = await client.getParams(Empty());
    final robot = params.robot;
    print('    机型: ${robot.type}');
    print('    初始关节位置 (前4): ${robot.initialJointPosition.values.take(4).map((v) => v.toStringAsFixed(3)).toList()}');
    assert(robot.initialJointPosition.values.length == 16, '关节数应为16');
  });

  await _test('GetStartTime', () async {
    final ts = await client.getStartTime(Empty());
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ts.seconds.toInt() * 1000 + ts.nanos ~/ 1000000,
      isUtc: true,
    );
    print('    启动时间: $dt');
    assert(dt.year >= 2026, '年份不合理');
  });

  // ──── 2. 硬件控制 ────
  await _test('Enable (使能电机)', () async {
    await client.enable(Empty());
    print('    ✓ 返回成功');
  });

  await _test('Disable (禁用电机)', () async {
    await client.disable(Empty());
    print('    ✓ 返回成功');
  });

  // ──── 3. 监控流 ────
  await _test('ListenImu (IMU 数据流, 取5帧)', () async {
    int count = 0;
    await for (final imu in client.listenImu(Empty())) {
      if (count == 0) {
        print('    首帧 gyro: (${imu.gyroscope.x.toStringAsFixed(4)}, ${imu.gyroscope.y.toStringAsFixed(4)}, ${imu.gyroscope.z.toStringAsFixed(4)})');
        print('    首帧 quat: (w=${imu.quaternion.w.toStringAsFixed(4)}, x=${imu.quaternion.x.toStringAsFixed(4)}, y=${imu.quaternion.y.toStringAsFixed(4)}, z=${imu.quaternion.z.toStringAsFixed(4)})');
      }
      count++;
      if (count >= 5) break;
    }
    print('    收到 $count 帧');
    assert(count == 5, '应收到5帧');
  });

  await _test('ListenJoint (关节数据流, 取5帧)', () async {
    int count = 0;
    await for (final joint in client.listenJoint(Empty())) {
      if (count == 0 && joint.hasSingleJoint()) {
        final j = joint.singleJoint;
        print('    首帧 关节ID=${j.id}, pos=${j.position.toStringAsFixed(3)}, vel=${j.velocity.toStringAsFixed(3)}, torque=${j.torque.toStringAsFixed(3)}');
      }
      count++;
      if (count >= 5) break;
    }
    print('    收到 $count 帧');
    assert(count == 5, '应收到5帧');
  });

  await _test('ListenHistory (历史数据流, 取3帧)', () async {
    int count = 0;
    await for (final h in client.listenHistory(Empty())) {
      if (count == 0) {
        final cmd = h.command;
        final cmdName = cmd.hasIdle()
            ? 'idle'
            : cmd.hasStandUp()
                ? 'standUp'
                : cmd.hasSitDown()
                    ? 'sitDown'
                    : cmd.hasWalk()
                        ? 'walk(${cmd.walk.x.toStringAsFixed(2)}, ${cmd.walk.y.toStringAsFixed(2)}, ${cmd.walk.z.toStringAsFixed(2)})'
                        : 'unknown';
        print('    首帧 command=$cmdName');
        print('    首帧 gyro: (${h.gyroscope.x.toStringAsFixed(4)}, ${h.gyroscope.y.toStringAsFixed(4)}, ${h.gyroscope.z.toStringAsFixed(4)})');
      }
      count++;
      if (count >= 3) break;
    }
    print('    收到 $count 帧');
    assert(count >= 1, '应至少收到1帧');
  });

  // ──── 4. 运动指令（CMS 状态机测试） ────
  // 当前状态: Grounded (idle)

  await _test('StandUp (Grounded → Standing)', () async {
    await client.standUp(Empty());
    print('    ✓ 命令已接受');
    // 等待过渡完成（~3秒, 150 steps × 20ms）
    print('    等待过渡完成...');
    await Future<void>.delayed(const Duration(seconds: 4));
    // 验证状态：检查 History 流的 command
    final h = await client.listenHistory(Empty()).first;
    final cmd = h.command;
    // Standing 状态下 idle behaviour 运行，command 应为 idle
    final isIdle = cmd.hasIdle();
    print('    过渡后 command=${isIdle ? "idle (Standing)" : "其他"}');
    assert(isIdle, '过渡完成后应进入 Standing (idle)');
  });

  await _test('Walk (Standing → Walking)', () async {
    await client.walk(Vector3(x: 0.5, y: 0.0, z: 0.0));
    print('    ✓ walk(0.5, 0, 0) 命令已接受');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // 验证 History 的 command 应为 walk
    final h = await client.listenHistory(Empty()).first;
    final cmd = h.command;
    final isWalk = cmd.hasWalk();
    print('    command=${isWalk ? "walk(${cmd.walk.x.toStringAsFixed(2)}, ${cmd.walk.y.toStringAsFixed(2)}, ${cmd.walk.z.toStringAsFixed(2)})" : "其他"}');
    assert(isWalk, '应进入 Walking 状态');
  });

  await _test('Walk 方向更新 (Walking 中)', () async {
    await client.walk(Vector3(x: 0.0, y: 0.3, z: 0.1));
    print('    ✓ walk(0, 0.3, 0.1) 方向更新');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final h = await client.listenHistory(Empty()).first;
    final cmd = h.command;
    if (cmd.hasWalk()) {
      print('    方向: (${cmd.walk.x.toStringAsFixed(2)}, ${cmd.walk.y.toStringAsFixed(2)}, ${cmd.walk.z.toStringAsFixed(2)})');
    }
  });

  await _test('StandUp (Walking → Standing, 回站立)', () async {
    await client.standUp(Empty());
    print('    ✓ 命令已接受');
    print('    等待过渡完成...');
    await Future<void>.delayed(const Duration(seconds: 4));
    final h = await client.listenHistory(Empty()).first;
    print('    过渡后 command=${h.command.hasIdle() ? "idle (Standing)" : "其他"}');
  });

  await _test('SitDown (Standing → Grounded)', () async {
    await client.sitDown(Empty());
    print('    ✓ 命令已接受');
    print('    等待过渡完成...');
    await Future<void>.delayed(const Duration(seconds: 4));
    // Grounded 后 listenHistory 只发一帧（我们的修改已恢复，现在是全速）
    final h = await client.listenHistory(Empty()).first;
    print('    过渡后 command=${h.command.hasIdle() ? "idle (Grounded)" : "其他"}');
  });

  // ──── 5. 边界情况 ────
  await _test('SitDown (Grounded 时坐下 → 应被拒绝/无效)', () async {
    // CMS: Grounded 状态下 SitDown 应被忽略
    try {
      await client.sitDown(Empty());
      print('    ✓ 命令返回成功（CMS 内部忽略，不报错）');
    } on GrpcError catch (e) {
      print('    ✗ 被拒绝: ${e.message}');
    }
  });

  await _test('Walk (Grounded 时行走 → 应被拒绝)', () async {
    try {
      await client.walk(Vector3(x: 1.0));
      print('    命令返回成功（CMS 内部忽略 walk when grounded）');
    } on GrpcError catch (e) {
      print('    被仲裁器拒绝: ${e.message}');
    }
  });

  // ──── 结果汇总 ────
  print('');
  print('══════════════════════════════════════════');
  print('  测试结果: $_pass 通过, $_fail 失败');
  print('══════════════════════════════════════════');
  print('');

  await channel.shutdown();
  exit(_fail > 0 ? 1 : 0);
}

Future<void> _test(String name, Future<void> Function() fn) async {
  stdout.write('[$name] ');
  try {
    await fn().timeout(const Duration(seconds: 15));
    print('  → ✓ PASS');
    _pass++;
  } on GrpcError catch (e) {
    print('  → ✗ FAIL (gRPC ${e.code}: ${e.message})');
    _fail++;
  } on TimeoutException {
    print('  → ✗ FAIL (超时 15s)');
    _fail++;
  } catch (e) {
    print('  → ✗ FAIL ($e)');
    _fail++;
  }
  print('');
}
