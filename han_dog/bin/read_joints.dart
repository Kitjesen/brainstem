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

  final pos = joint.position;
  final names = ['FR_hip','FR_thigh','FR_calf','FL_hip','FL_thigh','FL_calf',
                  'RR_hip','RR_thigh','RR_calf','RL_hip','RL_thigh','RL_calf',
                  'FR_foot','FL_foot','RR_foot','RL_foot'];
  print('Joint positions (rad):');
  for (var i = 0; i < 16; i++) {
    final deg = pos.values[i] * 180 / 3.14159;
    print('  [$i] ${names[i].padRight(10)} ${pos.values[i].toStringAsFixed(3)} rad  (${deg.toStringAsFixed(1)} deg)');
  }
  joint.dispose();
}
