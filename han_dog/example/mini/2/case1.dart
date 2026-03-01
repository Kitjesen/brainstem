import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:cms/cms.dart';

// dart format off
final standingPose = JointsMatrix(
  -0.1, -0.8,  1.8,
   0.1,  0.8, -1.8,
   0.1,  0.8, -1.8,
  -0.1, -0.8,  1.8,
  0, 0, 0, 0,
);
final kp = JointsMatrix(
    80, 100, 120,
    80, 100, 120,
    80, 100, 120,
    80, 100, 120,
    0, 0, 0, 0
);

final kd = JointsMatrix(
    10, 10, 15,
    10, 10, 15,
    10, 10, 15,
    10, 10, 15,
    1, 1, 1, 1
);
// dart format on

void main() async {
  Bloc.observer = SimpleBlocObserver();
  final clock = StreamController<void>.broadcast();
  final sim = SimSensorService(standingPose: standingPose);
  final brain = Brain(
    imu: sim,
    joint: sim,
    clock: clock,
    standingPose: standingPose,
    sittingPose: .zero(),
    historySize: 5,
    initialHistory: .new(
      gyroscope: .zero(),
      projectedGravity: .zero(),
      command: .idle(),
      jointPosition: standingPose,
      jointVelocity: .zero(),
      action: standingPose,
      nextAction: standingPose,
    ),
  )..loadModel('model/mini/2/policy_1119.onnx', inputName: "obs_history");
  final M m = M(brain)..add(Init());
  m.stream.listen(print);
  m.add(.walk(.new(0, 0, -0.8)));
  await Future.delayed(.zero); // !!! 完成 Init()
  final file = File('sample/case1_real.json');
  file.writeAsStringSync(''); // clear
  brain.walk.observationStream.listen((obs) {
    file.writeAsStringSync('$obs\n', mode: FileMode.append);
  });
  print(brain.memory.histories);

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
