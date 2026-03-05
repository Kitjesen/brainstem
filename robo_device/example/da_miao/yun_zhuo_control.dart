import 'package:robo_device/device.dart';
import 'package:robo_device_proto/device_proto.dart';

void main() async {
  final controller = SerialPortController<QPYunZhuoEvent, QPYunZhuoState>(
    '/dev/ttyACM0',
  );

  if (controller.open()) {
    print('Serial port opened successfully.');
  } else {
    print('Failed to open serial port.');
    return;
  }

  final actuator = PcanController<DMG6620Event, DMG6620State>(.usbbus1)..open();

  await Future.delayed(const .new(seconds: 1));
  actuator.add(.enable(1));
  await Future.delayed(const .new(seconds: 1));
  actuator.add(.enable(1));

  controller.state.listen((states) {
    for (final state in states) {
      final vel = (state.ch1Toch16[0] - 1500) / 450 * 2;
      actuator.add(.mit(1, velocity: vel, kd: 1));
    }
  });

  print('start');
  actuator.state.listen((state) {
    print(state);
  });
}
