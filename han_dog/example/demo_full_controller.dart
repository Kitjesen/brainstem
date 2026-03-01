import 'dart:async';

import 'package:frequency_watch/frequency_watch.dart';
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
  -0.1, -0.8,  1.8,   // FR: hip, thigh, calf
   0.1,  0.8, -1.8,   // FL: hip, thigh, calf
   0.1,  0.8, -1.8,   // RR: hip, thigh, calf
  -0.1, -0.8,  1.8,   // RL: hip, thigh, calf
  0, 0, 0, 0,         // foot joints
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
  )..loadModel('model/mini_policy6.onnx');
  brain.nextActionStream.listen((action) {
    joint.realActionExt(action);
  });

  // YUNZHUO 遥控器（通过 udev 规则固定为 /dev/yunzhuo）
  final controller = RealController('/dev/yunzhuo');
  if (!controller.open()) {
    print('Failed to open YUNZHUO controller on /dev/yunzhuo');
    return;
  }
  print('YUNZHUO controller opened on /dev/yunzhuo');

  final M m = M(brain)..add(Init());
  m.stream.listen(print);
  await Future<void>.delayed(.zero); // !!! 完成 Init()

  // 使用 YUNZHUO 控制器控制机器狗
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

  // ── gRPC 远程控制服务器 ──
  // 让 App（穹佩控制面板）可以通过网络远程控制机器狗。
  // gRPC 命令同样经过 ControlArbiter 仲裁，YUNZHUO 遥控器始终拥有更高优先级。
  final imuBroadcast = imu.stateStream.asBroadcastStream();
  final jointBroadcast = joint.reportStream.asBroadcastStream();
  final startTime = DateTime.now();
  msg.Duration elapsed() =>
      msg.Duration.fromDart(DateTime.now().difference(startTime));
  final grpcServer = Server.create(
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
    errorHandler: (error, trace) => print('gRPC server error: $error\n$trace'),
  );
  const grpcPort = 13145;
  await grpcServer.serve(port: grpcPort);
  print('gRPC remote control server started on port $grpcPort');

  // 频率监控：如果 IMU 或关节频率过低，自动切换到 idle
  RealFrequency.manager.onTick.listen((_) {
    if (imu.hz.value < 50 || joint.frequencyWatches.any((e) => e.value < 50)) {
      m.add(.fault('Sensor frequency too low '
          '(IMU: ${imu.hz.value} Hz, '
          'Joints: ${joint.frequencyWatches.map((e) => e.value).toList()})'));
    }
  });

  print('YUNZHUO controller ready. Use L1=standup, L2=sitdown, R1=idle, H=enable, red=disable');
  print('App remote control ready. Connect from 穹佩控制面板 to <robot-ip>:$grpcPort');

  Timer.periodic(const .new(milliseconds: 20), (_) {
    timeController.add(null);
    // 打印频率信息（调试用）
    // print('Imu: ${imu.hz.value} hz, Joint: ${joint.frequencyWatches.map((e) => e.value).toList()}');
  });
}

class SimpleBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    print('${bloc.runtimeType} $change');
  }
}
