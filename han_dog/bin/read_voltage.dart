import 'package:han_dog/han_dog.dart';

void main() async {
  final joint = RealJoint(
    fr: .usbbus4,
    fl: .usbbus3,
    rr: .usbbus2,
    rl: .usbbus1,
  );
  if (!joint.open()) {
    print('PCAN open failed');
    return;
  }
  joint.setReporting(true);
  await Future.delayed(Duration(milliseconds: 500));

  try {
    final voltages = await joint.readVoltage();
    print('Voltages:');
    for (var i = 0; i < 16; i++) {
      print('  [$i] ${voltages[i].toStringAsFixed(1)}V');
    }
    final valid = voltages.where((v) => v > 0).toList();
    if (valid.isNotEmpty) {
      print('Min: ${valid.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}V');
      print('Max: ${valid.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}V');
    }
  } catch (e) {
    print('Error: $e');
  }
  joint.dispose();
}
