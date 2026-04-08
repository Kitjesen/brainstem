import 'dart:async';
import 'dart:io';
import 'package:han_dog/han_dog.dart';
import 'package:vector_math/vector_math.dart';

void main() async {
  print('=== Xbox Gamepad Test ===');
  print('Device: /dev/input/js0');
  print('');

  XboxConfig config;
  try {
    config = await XboxConfig.loadFromFile('han_dog/config/xbox.json');
    print('Config loaded from xbox.json');
  } catch (_) {
    config = const XboxConfig();
    print('Using default config');
  }

  final xbox = XboxController('/dev/input/js0', config: config);
  if (!xbox.open()) {
    print('FAILED to open /dev/input/js0');
    return;
  }
  print('Controller opened!');
  print('');
  print('Press buttons and move sticks...');
  print('Press Ctrl+C to exit');
  print('');

  final subs = <StreamSubscription>[];

  // Direction
  var lastPrint = DateTime.now();
  subs.add(xbox.direction.listen((dir) {
    final now = DateTime.now();
    if (now.difference(lastPrint).inMilliseconds > 200 &&
        (dir.x.abs() > 0.01 || dir.y.abs() > 0.01 || dir.z.abs() > 0.01)) {
      lastPrint = now;
      print('  STICK  vx=${dir.x.toStringAsFixed(2).padLeft(6)} '
          'vy=${dir.y.toStringAsFixed(2).padLeft(6)} '
          'vyaw=${dir.z.toStringAsFixed(2).padLeft(6)}');
    }
  }));

  // Buttons
  subs.add(xbox.standup.listen((_) => print('  BTN A  (StandUp)')));
  subs.add(xbox.sitdown.listen((_) => print('  BTN X  (SitDown)')));
  subs.add(xbox.enabled.listen((e) => print('  BTN Y  (Enable=$e)')));
  subs.add(xbox.idle.listen((_) => print('  BTN RB (Idle/StandUp)')));
  subs.add(xbox.red.listen((_) => print('  BTN B  (Emergency Stop)')));
  subs.add(xbox.calibrate.listen((_) => print('  BTN Back (SetZero)')));
  subs.add(xbox.switchProfile.listen((_) => print('  BTN Start (SwitchProfile)')));

  // Run until Ctrl+C
  await ProcessSignal.sigint.watch().first;
  print('\nShutting down...');
  for (final s in subs) {
    await s.cancel();
  }
  xbox.dispose();
  print('Done.');
}
