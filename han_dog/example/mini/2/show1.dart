import 'dart:async';

import 'package:frequency_watch/frequency_watch.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:cms/cms.dart';

// dart format off
final inferKp = JointsMatrix(
    70, 80, 100,
    70, 80, 100,
    70, 80, 100,
    70, 80, 100,
    0, 0, 0, 0
);
final inferKd = JointsMatrix(
    15, 15, 15,
    15, 15, 15,
    15, 15, 15,
    15, 15, 15,
    1, 1, 1, 1
);
// dart format on

// dart format off
final standingPose = JointsMatrix(
  0, -0.64,  1.6,
  0,  0.64, -1.6,
  0,  0.64, -1.6,
  0, -0.64,  1.6,
  0, 0, 0, 0,
);
// dart format on

void main() async {
  Bloc.observer = SimpleBlocObserver();
  RealFrequency.manager.watch();

  final timeController = StreamController<void>.broadcast();
  final imu = RealImu()..open();
  final joint = RealJoint(
    fr: .usbbus3,
    fl: .usbbus1,
    rr: .usbbus4,
    rl: .usbbus2,
  )..open();

  // 标定只需要一次，然后注释掉
  // joint
  //   ..setZeroPosition()
  //   ..setZeroSigned()
  //   ..saveParameters();

  joint.setReporting(true);

  final brain = Brain(
    imu: imu,
    joint: joint,
    clock: timeController,
    standingPose: standingPose,
    sittingPose: .zero(),
    historySize: 5,
  )..loadModel('model/mini/2/policy_1119.onnx', inputName: "obs_history");
  brain.nextActionStream.listen((action) {
    // joint.realActionExt(action);
  });

  final controller = RealController();

  final M m = M(brain)..add(Init());
  m.stream.listen(print);
  await Future<void>.delayed(.zero); // !!! 完成 Init()
  final arbiter = ControlArbiter(m);
  RealControlDog(
    brain: brain,
    imu: imu,
    joint: joint,
    arbiter: arbiter,
    inferKd: inferKd,
    inferKp: inferKp,
    standUpKd: .fromList(.generate(16, (_) => 8.0)),
    standUpKp: .fromList(.generate(16, (_) => 200.0)),
    sitDownKd: .fromList(.generate(16, (_) => 8.0)),
    sitDownKp: .fromList(.generate(16, (_) => 200.0)),
    controller: controller,
  );

  RealFrequency.manager.onTick.listen((_) {
    if (imu.hz.value < 50 || joint.frequencyWatches.any((e) => e.value < 50)) {
      m.add(.fault('Sensor frequency too low '
          '(IMU: ${imu.hz.value} Hz, '
          'Joints: ${joint.frequencyWatches.map((e) => e.value).toList()})'));
    }
  });

  Timer.periodic(const .new(milliseconds: 20), (_) {
    timeController.add(null);

    print('Imu: ${imu.hz.value} hz');
    print(
      JointsMatrix.fromList(
        joint.frequencyWatches.map((e) => e.value.toDouble()).toList(),
      ),
    );
  });
}

class SimpleBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    print('${bloc.runtimeType} $change');
  }
}
