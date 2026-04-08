import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

void main() async {
  print('=== Xbox Gamepad Live Test ===');
  print('/dev/input/js0');
  print('Ctrl+C to exit\n');

  final file = File('/dev/input/js0');
  if (!file.existsSync()) {
    print('ERROR: /dev/input/js0 not found!');
    return;
  }

  // 状态
  final axes = <int, double>{};
  final buttons = <int, bool>{};
  final axisNames = {0:'LX', 1:'LY', 2:'LT', 3:'RX', 4:'RY', 5:'RT', 6:'DX', 7:'DY'};
  final btnNames = {0:'A', 1:'B', 2:'X', 3:'Y', 4:'LB', 5:'RB', 6:'Back', 7:'Start', 8:'Mode', 9:'LS', 10:'RS'};

  // 用独立 isolate 读阻塞设备，通过 stdin pipe 不行
  // 改用 Process 调 cat + 解析二进制
  final proc = await Process.start('cat', ['/dev/input/js0']);
  final buf = BytesBuilder();

  // 50Hz 刷新显示
  Timer.periodic(Duration(milliseconds: 100), (_) {
    // 清屏 + 打印
    stdout.write('\x1B[2J\x1B[H'); // clear + home
    stdout.writeln('=== Xbox Gamepad Live Test ===');
    stdout.writeln('');

    // 按钮状态
    stdout.write('  Buttons: ');
    for (var i = 0; i <= 10; i++) {
      final name = btnNames[i] ?? '$i';
      final on = buttons[i] ?? false;
      stdout.write(on ? '[$name] ' : ' $name  ');
    }
    stdout.writeln('\n');

    // 轴状态（柱状图）
    for (var i = 0; i < 8; i++) {
      final name = (axisNames[i] ?? '$i').padRight(3);
      final val = axes[i] ?? 0.0;
      final bar = _bar(val);
      stdout.writeln('  $name ${val.toStringAsFixed(2).padLeft(6)} $bar');
    }

    // 解析后的控制命令
    stdout.writeln('');
    final vx = -(axes[1] ?? 0.0);  // LY inverted
    final vy = axes[0] ?? 0.0;      // LX
    final vyaw = -(axes[3] ?? 0.0); // RX inverted
    final lt = ((axes[2] ?? -1.0) + 1) / 2;
    final rt = ((axes[5] ?? -1.0) + 1) / 2;
    var scale = 1.0;
    if (lt > 0.3) scale = 0.5;
    if (rt > 0.3) scale = 1.5;
    stdout.writeln('  Command: vx=${(vx*scale).toStringAsFixed(2)} vy=${(vy*scale).toStringAsFixed(2)} vyaw=${(vyaw*scale).toStringAsFixed(2)} scale=${scale.toStringAsFixed(1)}x');
    stdout.writeln('');
    stdout.writeln('  Ctrl+C to exit');
  });

  // 读事件流
  proc.stdout.listen((chunk) {
    buf.add(chunk);
    while (buf.length >= 8) {
      final bytes = buf.takeBytes();
      var offset = 0;
      while (offset + 8 <= bytes.length) {
        final bd = ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 8);
        final type = bd.getUint8(6) & 0x7F; // 去掉 init flag
        final number = bd.getUint8(7);
        final value = bd.getInt16(4, Endian.little);
        if (type == 2) {
          axes[number] = value / 32767.0;
        } else if (type == 1) {
          buttons[number] = value != 0;
        }
        offset += 8;
      }
      if (offset < bytes.length) {
        buf.add(bytes.sublist(offset));
      }
    }
  });

  // Ctrl+C
  ProcessSignal.sigint.watch().listen((_) {
    proc.kill();
    exit(0);
  });
}

String _bar(double val) {
  const width = 30;
  final center = width ~/ 2;
  final pos = ((val + 1) / 2 * width).round().clamp(0, width);
  final buf = StringBuffer();
  for (var i = 0; i <= width; i++) {
    if (i == center) {
      buf.write('|');
    } else if ((val >= 0 && i > center && i <= pos) ||
               (val < 0 && i >= pos && i < center)) {
      buf.write('█');
    } else {
      buf.write('·');
    }
  }
  return buf.toString();
}
