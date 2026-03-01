import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:cms/cms.dart';

// dart format off
final standingPose = JointsMatrix(
  0, -0.64,  1.6,
  0,  0.64, -1.6,
  0,  0.64, -1.6,
  0, -0.64,  1.6,
  0, 0, 0, 0,
);
final kp = JointsMatrix(
    120, 120, 120,
    120, 120, 120,
    120, 120, 120,
    120, 120, 120,
    0, 0, 0, 0
);

final kd = JointsMatrix(
    5, 5, 5,
    5, 5, 5,
    5, 5, 5,
    5, 5, 5,
    1, 1, 1, 1
);
// dart format on

void main() async {
  Bloc.observer = SimpleBlocObserver();
  final timeController = StreamController<void>.broadcast();
  final sim = SimSensorService(standingPose: standingPose);
  final brain = Brain(
    imu: sim,
    joint: sim,
    clock: timeController,
    standingPose: standingPose,
    sittingPose: .zero(),
  )..loadModel('model/mini_policy6.onnx');
  final M m = M(brain)..add(Init());
  m.stream.listen(print);
  await Future.delayed(.zero); // !!! 完成 Init()
  final server = Server.create(
    services: [
      UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.simulation,
        simInjector: sim,
        gains: GainManager(
          inferKp: kp, inferKd: kd,
          standUpKp: kp, standUpKd: kd,
          sitDownKp: kp, sitDownKd: kd,
        ),
      ),
    ],
    errorHandler: (error, trace) => print('Server error: $error\n$trace'),
  );
  print('Starting simulation server on port 13145...');
  await server.serve(port: 13145);
}

class SimpleBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    print('${bloc.runtimeType} $change');
  }
}
