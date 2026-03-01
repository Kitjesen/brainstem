import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_message/han_dog_message.dart' as msg;
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:cms/cms.dart';

// dart format off
final inferKp = JointsMatrix(
    180, 180, 180,
    180, 180, 180,
    180, 180, 180,
    180, 180, 180,
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
  )..loadModel('model/mini_policy6.onnx');
  brain.nextActionStream.listen((action) {
    // joint.realActionExt(action);
  });

  final M m = M(brain)..add(Init());
  m.stream.listen(print);
  await Future<void>.delayed(.zero); // !!! 完成 Init()
  final arbiter = ControlArbiter(m);
  final imuBroadcast = imu.stateStream.asBroadcastStream();
  final jointBroadcast = joint.reportStream.asBroadcastStream();
  final startTime = DateTime.now();
  msg.Duration elapsed() =>
      msg.Duration.fromDart(DateTime.now().difference(startTime));
  final server = Server.create(
    services: [
      UnifiedCmsServer(
        brain: brain,
        m: m,
        mode: CmsMode.hardware,
        arbiter: arbiter,
        robotType: msg.RobotType.MINI,
        imuStreamFactory: () => imuBroadcast.expand((s) => s).map(
              (s) => msg.Imu(
                gyroscope: msg.Vector3(
                    x: s.gyroscope.x, y: s.gyroscope.y, z: s.gyroscope.z),
                quaternion: msg.Quaternion(
                    w: s.quaternion.w,
                    x: s.quaternion.x,
                    y: s.quaternion.y,
                    z: s.quaternion.z),
                timestamp: elapsed(),
              ),
            ),
        jointStreamFactory: () => jointBroadcast.map(
              (r) => msg.Joint(
                singleJoint: msg.SingleJoint(
                  id: r.$1,
                  position: r.$2.position,
                  velocity: r.$2.velocity,
                  torque: r.$2.torque,
                  status: r.$2.status.value,
                ),
                timestamp: elapsed(),
              ),
            ),
      ),
    ],
    errorHandler: (error, trace) => print('Server error: $error\n$trace'),
  );
  print('Starting hardware server on port 13145...');

  Timer.periodic(const .new(milliseconds: 20), (_) {
    timeController.add(null);
    // print(joint);
  });

  await server.serve(port: 13145);
}

class SimpleBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    print('${bloc.runtimeType} $change');
  }
}
