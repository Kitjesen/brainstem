import 'package:han_dog/han_dog.dart';

void main() async {
  print('Testing Xbox controller on /dev/input/js0...');
  final xbox = XboxController('/dev/input/js0');
  if (!xbox.open()) {
    print('FAILED to open /dev/input/js0');
    return;
  }
  print('Opened! Reading 5 seconds of events...');
  print('(move sticks or press buttons)');

  var count = 0;
  final sub = xbox.direction.listen((dir) {
    count++;
    if (count % 10 == 0) {
      print(
        '  direction: vx=${dir.x.toStringAsFixed(2)} vy=${dir.y.toStringAsFixed(2)} vyaw=${dir.z.toStringAsFixed(2)}',
      );
    }
  });

  final btnSub = xbox.standup.listen((_) => print('  >> A pressed (standup)'));
  final btn2Sub = xbox.sitdown.listen((_) => print('  >> X pressed (sitdown)'));
  final btn3Sub = xbox.enabled.listen(
    (e) => print('  >> Y pressed (enable=$e)'),
  );

  await Future<void>.delayed(const Duration(seconds: 5));
  await sub.cancel();
  await btnSub.cancel();
  await btn2Sub.cancel();
  await btn3Sub.cancel();
  xbox.dispose();
  print('Done. Events received: $count');
}
