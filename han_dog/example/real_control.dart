import 'package:han_dog/src/real_controller.dart';

void main() {
  final controller = RealController();
  // controller.direction.listen((dir) {
  //   print('Direction: $dir');
  // });
  controller.standup.listen((state) {
    print('standup: $state');
  });
  controller.sitdown.listen((state) {
    print('sitdown: $state');
  });
  // controller.enabled.listen((enabled) {
  //   print('enabled: $enabled');
  // });

  controller.stateStream.listen((state) {
    print('State: $state');
  });
  if (controller.open() case final ret when ret == false) {
    print('Failed to open controller port');
    controller.dispose();
    return;
  }
}
