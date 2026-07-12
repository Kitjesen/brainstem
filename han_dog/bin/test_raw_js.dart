import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';

void _readLoop(SendPort port) {
  final file = File('/dev/input/js0').openSync(mode: FileMode.read);
  while (true) {
    final buf = Uint8List(8);
    file.readIntoSync(buf);
    final bd = ByteData.sublistView(buf);
    final type = bd.getUint8(6);
    final number = bd.getUint8(7);
    final value = bd.getInt16(4, Endian.little);
    // Skip init events (type >= 0x80)
    if (type < 0x80) {
      port.send('type=$type num=$number val=$value');
    }
  }
}

void main() async {
  print('=== Raw Joystick Test ===');
  print('Reading /dev/input/js0 via Isolate...');
  print('Press buttons / move sticks (15s)');
  print('');

  final recv = ReceivePort();
  await Isolate.spawn(_readLoop, recv.sendPort);

  var count = 0;
  final sub = recv.listen((msg) {
    count++;
    print('  [$count] $msg');
  });

  await Future<void>.delayed(const Duration(seconds: 15));
  await sub.cancel();
  recv.close();
  print('\nTotal events: $count');
  exit(0);
}
