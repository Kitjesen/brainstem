import 'dart:async';
import 'dart:io';

import 'package:han_dog/han_dog.dart';

void main() async {
  final js = Platform.environment['HAN_DOG_XBOX_DEVICE'] ?? '/dev/input/js0';
  final hidraw =
      Platform.environment['HAN_DOG_NC500_HIDRAW_DEVICE'] ?? '/dev/hidraw0';

  XboxConfig config;
  try {
    config = await XboxConfig.loadFromFile('han_dog/config/xbox.json');
    print('Config loaded: han_dog/config/xbox.json');
  } catch (_) {
    config = const XboxConfig();
    print('Using default Xbox config');
  }

  final pad = XboxNc500Controller(
    js,
    nc500HidrawDevice: hidraw,
    config: config,
  );
  if (!pad.open()) {
    print('No usable Xbox/NC500 joystick.');
    print('Expected standard joystick node: $js or /dev/input/js*');
    print('NC500 hidraw/update node, if present: $hidraw');
    return;
  }

  print(
    'Xbox/NC500 opened. This test only prints input; it does not move motors.',
  );
  final stopwatch = Stopwatch()..start();
  String ts() => '${stopwatch.elapsedMilliseconds.toString().padLeft(6)}ms';
  var wasCentered = true;
  final subs = <StreamSubscription<Object?>>[
    pad.direction.listen((v) {
      final centered =
          v.x.abs() <= 0.01 && v.y.abs() <= 0.01 && v.z.abs() <= 0.01;
      if (centered) {
        if (!wasCentered) print('${ts()} CENTER vx=0.00 vy=0.00 vyaw=0.00');
        wasCentered = true;
        return;
      }
      wasCentered = false;
      print(
        '${ts()} STICK vx=${v.x.toStringAsFixed(2)} '
        'vy=${v.y.toStringAsFixed(2)} '
        'vyaw=${v.z.toStringAsFixed(2)}',
      );
    }),
    pad.standup.listen((_) => print('${ts()} BTN StandUp')),
    pad.sitdown.listen((_) => print('${ts()} BTN SitDown')),
    pad.enabled.listen((v) => print('${ts()} BTN Enable=$v')),
    pad.idle.listen((_) => print('${ts()} BTN Idle')),
    pad.red.listen((_) => print('${ts()} BTN EmergencyStop')),
    pad.calibrate.listen((_) => print('${ts()} BTN SetZero')),
    pad.switchProfile.listen((_) => print('${ts()} BTN SwitchProfile')),
  ];

  await Future<void>.delayed(const Duration(seconds: 30));
  for (final sub in subs) {
    await sub.cancel();
  }
  pad.dispose();
}
