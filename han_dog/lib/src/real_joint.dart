import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:frequency_watch/frequency_watch.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:han_dog_brain/han_dog_brain.dart';

final _log = Logger('han_dog.real_joint');

RSStateReport get _defaultReport => .new(
  hostId: 0,
  canId: 0,
  status: .fromValue(0),
  position: 0,
  velocity: 0,
  torque: 0,
  temperature: 0,
  errors: .new(0),
);

class RealJoint implements JointService, MotorService {
  final List<PcanController<RSEvent, RSState>> pcans;

  PcanController<RSEvent, RSState> get fr => pcans[0];
  PcanController<RSEvent, RSState> get fl => pcans[1];
  PcanController<RSEvent, RSState> get rr => pcans[2];
  PcanController<RSEvent, RSState> get rl => pcans[3];

  List<RSStateReport> get frStatus => status[0];
  List<RSStateReport> get flStatus => status[1];
  List<RSStateReport> get rrStatus => status[2];
  List<RSStateReport> get rlStatus => status[3];

  @override
  JointsMatrix get initialPosition => .zero();
  @override
  JointsMatrix get initialVelocity => .zero();

  @override
  JointsMatrix get position => thetas;
  @override
  JointsMatrix get velocity => omegas;

  JointsMatrix get thetas => _cachedThetas ??= .fromList([
    frStatus[0].position,
    frStatus[1].position,
    frStatus[2].position,
    flStatus[0].position,
    flStatus[1].position,
    flStatus[2].position,
    rrStatus[0].position,
    rrStatus[1].position,
    rrStatus[2].position,
    rlStatus[0].position,
    rlStatus[1].position,
    rlStatus[2].position,
    frStatus[3].position,
    flStatus[3].position,
    rrStatus[3].position,
    rlStatus[3].position,
  ]);
  JointsMatrix get omegas => _cachedOmegas ??= .fromList([
    frStatus[0].velocity,
    frStatus[1].velocity,
    frStatus[2].velocity,
    flStatus[0].velocity,
    flStatus[1].velocity,
    flStatus[2].velocity,
    rrStatus[0].velocity,
    rrStatus[1].velocity,
    rrStatus[2].velocity,
    rlStatus[0].velocity,
    rlStatus[1].velocity,
    rlStatus[2].velocity,
    frStatus[3].velocity,
    flStatus[3].velocity,
    rrStatus[3].velocity,
    rlStatus[3].velocity,
  ]);

  final status = <List<RSStateReport>>[
    .filled(4, _defaultReport), // leg 1
    .filled(4, _defaultReport), // leg 2
    .filled(4, _defaultReport), // leg 3
    .filled(4, _defaultReport), // leg 4
  ];
  final frequencyWatches = List.generate(16, (_) => RealFrequency());

  late final List<StreamSubscription<RSState>> subscriptions;

  final _reportController = StreamController<(int, RSStateReport)>.broadcast();
  Stream<(int, RSStateReport)> get reportStream => _reportController.stream;

  // Cached JointsMatrix values, invalidated on status update
  JointsMatrix? _cachedThetas;
  JointsMatrix? _cachedOmegas;

  RealJoint({
    required PcanChannel fr,
    required PcanChannel fl,
    required PcanChannel rr,
    required PcanChannel rl,
  }) : pcans = [.new(fr), .new(fl), .new(rr), .new(rl)] {
    subscriptions = [
      _listenLeg(0),
      _listenLeg(1),
      _listenLeg(2),
      _listenLeg(3),
    ];
  }

  StreamSubscription<RSState> _listenLeg(int legId) {
    return pcans[legId].state.listen((state) {
      switch (state) {
        case RSStateReport(canId: final targetId)
            when targetId >= 1 && targetId <= 4:
          status[legId][targetId - 1] = state;
          _cachedThetas = null;
          _cachedOmegas = null;
          frequencyWatches[legId * 4 + targetId - 1].add(1);
          _reportController.add((legId * 4 + targetId - 1, state));
        default:
      }
    });
  }

  bool open() {
    bool allOpened = true;
    for (int i = 0; i < pcans.length; i++) {
      if (!pcans[i].open()) {
        _log.severe('PCAN leg $i open failed');
        allOpened = false;
      }
    }
    return allOpened;
  }

  @override
  Future<void> enable() async {
    for (final pcan in pcans) {
      for (int i = 1; i <= 4; i++) {
        pcan.add(.enable(i));
      }
    }
  }

  @override
  Future<void> disable() async {
    for (final pcan in pcans) {
      for (int i = 1; i <= 4; i++) {
        pcan.add(.disable(i));
      }
    }
  }

  void setReporting([bool enable = true]) {
    for (final pcan in pcans) {
      for (int i = 1; i <= 4; i++) {
        pcan.add(.setReporting(i, enable: enable));
      }
    }
  }

  JointsMatrix kpExt = .zero();
  JointsMatrix kdExt = .zero();

  @override
  void sendAction(JointsMatrix action) => realActionExt(action);

  void realActionExt(JointsMatrix action) {
    // action = action * actionRatio;
    _realActionExt(action, kpExt, kdExt);
  }

  void _realActionExt(JointsMatrix a, JointsMatrix kp, JointsMatrix kd) {
    // print(action);
    // print(kp);
    // print(kd);
    // return;
    fr.add(.control(1, position: a.frHip, kp: kp.frHip, kd: kd.frHip));
    fr.add(.control(2, position: a.frThigh, kp: kp.frThigh, kd: kd.frThigh));
    fr.add(.control(3, position: a.frCalf, kp: kp.frCalf, kd: kd.frCalf));
    fr.add(.control(4, velocity: a.frFoot, kd: kd.frFoot));

    fl.add(.control(1, position: a.flHip, kp: kp.flHip, kd: kd.flHip));
    fl.add(.control(2, position: a.flThigh, kp: kp.flThigh, kd: kd.flThigh));
    fl.add(.control(3, position: a.flCalf, kp: kp.flCalf, kd: kd.flCalf));
    fl.add(.control(4, velocity: a.flFoot, kd: kd.flFoot));

    rr.add(.control(1, position: a.rrHip, kp: kp.rrHip, kd: kd.rrHip));
    rr.add(.control(2, position: a.rrThigh, kp: kp.rrThigh, kd: kd.rrThigh));
    rr.add(.control(3, position: a.rrCalf, kp: kp.rrCalf, kd: kd.rrCalf));
    rr.add(.control(4, velocity: a.rrFoot, kd: kd.rrFoot));

    rl.add(.control(1, position: a.rlHip, kp: kp.rlHip, kd: kd.rlHip));
    rl.add(.control(2, position: a.rlThigh, kp: kp.rlThigh, kd: kd.rlThigh));
    rl.add(.control(3, position: a.rlCalf, kp: kp.rlCalf, kd: kd.rlCalf));
    rl.add(.control(4, velocity: a.rlFoot, kd: kd.rlFoot));
  }

  void dispose() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
    _reportController.close();
    close();
  }

  void close() {
    for (final pcan in pcans) {
      pcan.close();
    }
  }

  void setZeroPosition() {
    for (final pcan in pcans) {
      pcan.setZeroPosition();
    }
  }

  void setZeroSigned() {
    for (final pcan in pcans) {
      pcan.setZeroSigned();
    }
  }

  void saveParameters() {
    for (final pcan in pcans) {
      pcan.saveParameters();
    }
  }

  @override
  String toString() {
    return '''
Motors:
fr: ${frStatus.map(formatReport).join(', ')}
fl: ${flStatus.map(formatReport).join(', ')}
rr: ${rrStatus.map(formatReport).join(', ')}
rl: ${rlStatus.map(formatReport).join(', ')}
''';
  }
}

String formatReport(RSStateReport? report) {
  if (report == null) {
    return 'null';
  }
  return '(θ: ${report.position.toDegree().toStringAsFixed(2)}, '
      'ω: ${report.velocity.toStringAsFixed(2)}, '
      'τ: ${report.torque.toStringAsFixed(2)}, '
      '${report.errors.errors.isEmpty ? 'Ok' : 'Err'})';
}

extension on double {
  double toDegree() {
    return this / pi * 180;
  }
}

extension LegExt on PcanController<RSEvent, RSState> {
  void setZeroPosition() {
    for (int id = 1; id <= 4; id++) {
      add(.setZero(id));
    }
  }

  void control(
    double kp,
    double kd,
    double footKd,
    double hip,
    double thigh,
    double calf,
    double foot,
  ) {
    add(.control(1, kp: kp, kd: kd, position: hip, torque: 0));
    add(.control(2, kp: kp, kd: kd, position: thigh, torque: 0));
    add(.control(3, kp: kp, kd: kd, position: calf, torque: 0));
    add(.control(4, kd: footKd, velocity: foot, torque: 0));
  }

  void setZeroSigned() {
    for (int id = 1; id <= 4; id++) {
      add(.set(id, setter: .zeroSta(true)));
    }
  }

  void saveParameters() {
    for (int id = 1; id <= 4; id++) {
      add(.saveData(id));
    }
  }
}
