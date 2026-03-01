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
    70, 100, 120,
    70, 100, 120,
    70, 100, 120,
    70, 100, 120,
    0, 0, 0, 0
);

final kd = JointsMatrix(
    10, 15, 20,
    10, 15, 20,
    10, 15, 20,
    10, 15, 20,
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
  )..loadModel('model/mini/2/policy_1119.onnx', inputName: "obs_history");
  final M m = M(brain)..add(Init());
  m.stream.listen(print);
  await Future.delayed(.zero); // !!! 完成 Init()

  final logFile = await File('logs/cur.txt').create(recursive: true);

  brain.memory.historyStream.listen((history) {
    // print('history: $history');
    logFile.writeAsStringSync('$history\n', mode: FileMode.append);
  });
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
