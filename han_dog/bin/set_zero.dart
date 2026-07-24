import 'package:han_dog/han_dog.dart';

void main() async {
  final joint = RealJoint(
    fr: .usbbus4,
    fl: .usbbus3,
    rr: .usbbus2,
    rl: .usbbus1,
  );
  if (!joint.open()) { print('PCAN open failed'); return; }
  joint.setReporting(true);
  await Future.delayed(Duration(milliseconds: 500));

  print('Current positions before zero:');
  final pos = joint.position;
  for (var i = 0; i < 16; i++) {
    print('  [$i] ${pos.values[i].toStringAsFixed(3)} rad');
  }

  print('Setting zero...');
  final ok = await joint.setZero();
  print('SetZero: $ok');

  await Future.delayed(Duration(milliseconds: 500));
  print('Positions after zero:');
  final pos2 = joint.position;
  for (var i = 0; i < 16; i++) {
    print('  [$i] ${pos2.values[i].toStringAsFixed(3)} rad');
  }
  joint.dispose();
}
