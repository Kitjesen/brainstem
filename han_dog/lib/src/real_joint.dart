import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:frequency_watch/frequency_watch.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:han_dog_brain/han_dog_brain.dart';

final _log = Logger('han_dog.real_joint');

/// Learned walking uses the active profile's gains without a global override.
/// Stand-up and sit-down also keep their profile values unchanged.
const double hanDogWalkingHipKdScale = 1.0;

JointsMatrix applyHanDogWalkingHipKp(JointsMatrix kp) => kp;

JointsMatrix applyHanDogWalkingHipKdScale(JointsMatrix kd) =>
    kd.scale(hanDogWalkingHipKdScale, 1.0, 1.0, 1.0);

// ─── Motor fault event ───────────────────────────────────────────────────────

class MotorFaultEvent {
  final int jointIndex;
  final Set<RSError> errors;
  final int errorBits;
  final RSStatus status;
  final double position;
  final double velocity;
  final double torque;
  final double temperature;

  const MotorFaultEvent({
    required this.jointIndex,
    required this.errors,
    required this.errorBits,
    required this.status,
    required this.position,
    required this.velocity,
    required this.torque,
    required this.temperature,
  });

  bool get isHealthy => errors.isEmpty;

  @override
  String toString() =>
      'MotorFaultEvent(joint=$jointIndex, $errors, errorBits=0x${errorBits.toRadixString(16)}, '
      'status=$status, pos=${position.toStringAsFixed(3)}, '
      'vel=${velocity.toStringAsFixed(3)}, torque=${torque.toStringAsFixed(3)}, '
      'temp=${temperature.toStringAsFixed(1)}?C)';
}

/// Communication-type-21 full fault feedback from a RobStride motor.
class MotorFullFaultEvent {
  final int jointIndex;
  final int faultBits;
  final Set<RSError> decodedErrors;

  const MotorFullFaultEvent({
    required this.jointIndex,
    required this.faultBits,
    required this.decodedErrors,
  });
}

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
  bool get _motorCommandsAllowed =>
      Platform.environment['HAN_DOG_ALLOW_MOTOR_ENABLE']?.toLowerCase() ==
      'true';

  bool _blockedActionLogged = false;
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
  final lastReportAt = List<DateTime?>.filled(16, null);

  late final List<StreamSubscription<RSState>> subscriptions;

  final _reportController = StreamController<(int, RSStateReport)>.broadcast();
  Stream<(int, RSStateReport)> get reportStream => _reportController.stream;

  final _motorFaultController = StreamController<MotorFaultEvent>.broadcast();
  Stream<MotorFaultEvent> get motorFaultStream => _motorFaultController.stream;

  final _fullFaultController =
      StreamController<MotorFullFaultEvent>.broadcast();
  Stream<MotorFullFaultEvent> get fullFaultStream =>
      _fullFaultController.stream;

  // Cached JointsMatrix values, invalidated on status update
  JointsMatrix? _cachedThetas;
  JointsMatrix? _cachedOmegas;

  RealJoint({
    required PcanChannel fr,
    required PcanChannel fl,
    required PcanChannel rr,
    required PcanChannel rl,
  }) : this.withControllers([.new(fr), .new(fl), .new(rr), .new(rl)]);

  RealJoint.withControllers(this.pcans) {
    subscriptions = [
      _listenLeg(0),
      _listenLeg(1),
      _listenLeg(2),
      _listenLeg(3),
    ];
  }

  StreamSubscription<RSState> _listenLeg(int legId) {
    return pcans[legId].state.listen(
      (state) {
        switch (state) {
          case RSStateReport(canId: final targetId)
              when targetId >= 1 && targetId <= 4:
            status[legId][targetId - 1] = state;
            _cachedThetas = null;
            _cachedOmegas = null;
            frequencyWatches[legId * 4 + targetId - 1].add(1);
            lastReportAt[legId * 4 + targetId - 1] = DateTime.now();
            _reportController.add((legId * 4 + targetId - 1, state));
            final jointIdx = targetId <= 3
                ? legId * 3 + (targetId - 1)
                : 12 + legId;
            _motorFaultController.add(
              MotorFaultEvent(
                jointIndex: jointIdx,
                errors: state.errors.errors,
                errorBits: state.errors.value,
                status: state.status,
                position: state.position,
                velocity: state.velocity,
                torque: state.torque,
                temperature: state.temperature,
              ),
            );
          case RSStateError(canId: final targetId)
              when targetId >= 1 && targetId <= 4:
            final jointIdx = targetId <= 3
                ? legId * 3 + (targetId - 1)
                : 12 + legId;
            _fullFaultController.add(
              MotorFullFaultEvent(
                jointIndex: jointIdx,
                faultBits: state.errors.value,
                decodedErrors: state.errors.errors,
              ),
            );
          default:
        }
      },
      onError: (Object error, StackTrace st) {
        _log.severe('PCAN leg $legId stream error', error, st);
      },
      onDone: () {
        _log.warning('PCAN leg $legId stream closed unexpectedly');
      },
    );
  }

  bool open() {
    bool allOpened = true;
    final opened = <PcanController<RSEvent, RSState>>[];
    for (int i = 0; i < pcans.length; i++) {
      if (pcans[i].open()) {
        opened.add(pcans[i]);
      } else {
        _log.severe('PCAN leg $i open failed');
        allOpened = false;
      }
    }
    if (opened.isNotEmpty) {
      _sendDisableAll(targets: opened);
      _log.info('Startup motor disable sent to ${opened.length} PCAN channels');
    }
    if (allOpened) {
      _log.info('All ${pcans.length} PCAN channels opened');
    }
    return allOpened;
  }

  @override
  Future<void> enable() async {
    if (_disableOperation != null || _disableFailed) {
      throw StateError(
        'Enable blocked: motor disable has not been confirmed; '
        'retry disable and check CAN feedback',
      );
    }
    if (!_motorCommandsAllowed) {
      _log.warning(
        'Motor enable blocked: HAN_DOG_ALLOW_MOTOR_ENABLE is not true',
      );
      _sendDisableAll();
      return;
    }
    for (final pcan in pcans) {
      for (int i = 1; i <= 4; i++) {
        pcan.add(.enable(i));
      }
    }
    _disableRequested = false;
  }

  bool _disableRequested = false;
  bool _disableFailed = false;
  Future<void>? _disableOperation;
  bool lastDisableConfirmed = false;
  List<int> unconfirmedDisableJoints = const [];

  @override
  Future<void> disable({bool clearErrors = false}) {
    // This gate is synchronous: even stale action subscriptions cannot send
    // motion while the stop is being delivered/verified.
    _disableRequested = true;
    if (_disableOperation != null) {
      if (clearErrors) _sendDisableAll(clearErrors: true);
      return _disableOperation!;
    }
    return _disableOperation = _disableAndVerify(clearErrors).whenComplete(() {
      _disableOperation = null;
    });
  }

  Future<void> _disableAndVerify(bool clearErrors) async {
    lastDisableConfirmed = false;
    final watch = Stopwatch()..start();
    final seenAt = List<int>.filled(16, -1);
    final disabled = List<bool>.filled(16, false);
    final sub = reportStream.listen((event) {
      seenAt[event.$1] = watch.elapsedMilliseconds;
      disabled[event.$1] = event.$2.status == RSStatus.reset;
    });
    try {
      for (final pcan in pcans) {
        pcan.clearPendingWrites();
      }
      setReporting(true);
      _sendDisableAll(clearErrors: clearErrors);
      while (!_disposed && watch.elapsedMilliseconds < 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final missing = <int>[];
        for (var i = 0; i < 16; i++) {
          if (!disabled[i] ||
              seenAt[i] < 0 ||
              watch.elapsedMilliseconds - seenAt[i] > 100) {
            missing.add(i);
          }
        }
        if (missing.isEmpty) {
          lastDisableConfirmed = true;
          _disableFailed = false;
          unconfirmedDisableJoints = const [];
          _log.info(
            'Motor disable confirmed by fresh feedback from all 16 motors',
          );
          return;
        }
        unconfirmedDisableJoints = [
          for (final i in missing)
            i % 4 == 3 ? 12 + i ~/ 4 : (i ~/ 4) * 3 + i % 4,
        ];
        for (final i in missing) {
          pcans[i ~/ 4].add(
            RSEvent.disable(i % 4 + 1, clearErrors: clearErrors),
          );
        }
      }
      _disableFailed = true;
      _log.severe(
        'MOTOR DISABLE UNCONFIRMED: joints=$unconfirmedDisableJoints; '
        'motion remains blocked and re-enable is refused',
      );
    } finally {
      await sub.cancel();
    }
  }

  void _sendDisableAll({
    bool clearErrors = false,
    Iterable<PcanController<RSEvent, RSState>>? targets,
  }) {
    for (final pcan in targets ?? pcans) {
      for (int i = 1; i <= 4; i++) {
        pcan.add(.disable(i, clearErrors: clearErrors));
      }
    }
  }

  /// ?????? fault??????????????????????
  void clearFaults() {
    _sendDisableAll(clearErrors: true);
  }

  /// 设置足轮 CAN 通信超时（微秒）。程序崩溃后轮子在超时后自动停转。
  void setFootWheelCantimeout(int microseconds) {
    for (final pcan in pcans) {
      pcan.add(RSEvent.set(4, setter: RSSetter.cantimeout(microseconds)));
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
    if (_disableRequested) return;
    if (!_motorCommandsAllowed) {
      if (!_blockedActionLogged) {
        _blockedActionLogged = true;
        _log.warning(
          'Motor action frames blocked: HAN_DOG_ALLOW_MOTOR_ENABLE is not true',
        );
      }
      return;
    }
    // 最后一道安全门：NaN/Inf 绝不能到达 CAN 总线。
    if (action.hasNonFinite || kpExt.hasNonFinite || kdExt.hasNonFinite) {
      _log.severe(
        'realActionExt rejected: non-finite values detected '
        '(action=${action.hasNonFinite}, kp=${kpExt.hasNonFinite}, '
        'kd=${kdExt.hasNonFinite})',
      );
      return;
    }
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

  // ─── Flat-index helpers ────────────────────────────────────────────────────

  /// Converts JointsMatrix flat index (0–15) to (legId, canId).
  /// idx 0–11 → legId = idx ~/3, canId = idx%3+1
  /// idx 12–15 → legId = idx-12, canId = 4
  (int, int) _flatIndexToLegCan(int idx) {
    if (idx < 12) return (idx ~/ 3, idx % 3 + 1);
    return (idx - 12, 4);
  }

  /// Whether joint [idx] is actively communicating (>0 Hz in last 1s).
  bool isOnline(int idx) {
    if (idx < 0 || idx >= 16) return false;
    final (legId, canId) = _flatIndexToLegCan(idx);
    return frequencyWatches[legId * 4 + canId - 1].value > 0;
  }

  /// Returns the current report frequency for flat joint [idx].
  ///
  /// The internal watch list is in CAN report order, while policy actions use
  /// the flat 16-joint order. Keep this mapping in one place.
  int feedbackFrequency(int idx) {
    if (idx < 0 || idx >= 16) return 0;
    final (legId, canId) = _flatIndexToLegCan(idx);
    return frequencyWatches[legId * 4 + canId - 1].value;
  }

  /// Latest report without consulting the one-second frequency bucket.
  RSStateReport? latestReport(int idx) {
    if (idx < 0 || idx >= 16) return null;
    final (legId, canId) = _flatIndexToLegCan(idx);
    return status[legId][canId - 1];
  }

  /// Wall-clock time of the latest real report for flat joint [idx].
  DateTime? latestReportAt(int idx) {
    if (idx < 0 || idx >= 16) return null;
    final (legId, canId) = _flatIndexToLegCan(idx);
    return lastReportAt[legId * 4 + canId - 1];
  }

  /// Returns the latest report for flat joint [idx], or null if out of range
  /// or if the motor is offline (0 Hz — data is stale).
  RSStateReport? getReport(int idx) {
    if (idx < 0 || idx >= 16) return null;
    if (!isOnline(idx)) return null; // stale data, motor not communicating
    final (legId, canId) = _flatIndexToLegCan(idx);
    return status[legId][canId - 1];
  }

  /// Sends a single disable+clearErrors command to joint [idx].
  void clearFaultSingle(int idx) {
    if (idx < 0 || idx >= 16) return;
    final (legId, canId) = _flatIndexToLegCan(idx);
    pcans[legId].add(.disable(canId, clearErrors: true));
  }

  /// Read the small set of supported private diagnostics for one motor.
  /// This is called only after a fault and adds no traffic during normal motion.
  Future<Map<String, double>> readFaultDiagnostics(
    int idx, {
    Duration timeout = const Duration(milliseconds: 180),
  }) async {
    if (idx < 0 || idx >= 16) return const {};
    final (legId, canId) = _flatIndexToLegCan(idx);
    final values = <String, double>{};
    final sub = pcans[legId].state.listen((state) {
      if (state is! RSStateGetter || state.canId != canId) return;
      final getter = state.getter;
      if (getter is RSGetterVbus) {
        values['vbus'] = getter.value;
      } else if (getter is RSGetterIqf) {
        values['iqf'] = getter.value;
      } else if (getter is RSGetterLimitCur) {
        values['limitCur'] = getter.value;
      }
    });

    pcans[legId]
      ..add(RSEvent.get(canId, key: RSKey.vbus))
      ..add(RSEvent.get(canId, key: RSKey.iqf))
      ..add(RSEvent.get(canId, key: RSKey.limitCur));
    await Future<void>.delayed(timeout);
    await sub.cancel();
    return values;
  }

  /// 电机清零：把当前位置标记为零点，设置符号，保存参数。
  Future<bool> setZero() async {
    setZeroPosition();
    setZeroSigned();
    saveParameters();
    return true;
  }

  // ─── Voltage reading ────────────────────────────────────────────────────

  /// 读取全部 16 个电机的总线电压 (V)。
  /// 返回 16 个 double，顺序同 JointsMatrix（FR hip/thigh/calf, FL..., feet）。
  /// 超时未响应的电机返回 0.0。
  Future<List<double>> readVoltage({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final voltages = List<double>.filled(16, 0.0);

    // 用每条腿的 PcanController 监听 getter 响应
    final legSubs = <StreamSubscription<RSState>>[];
    for (int legId = 0; legId < 4; legId++) {
      legSubs.add(
        pcans[legId].state.listen((state) {
          if (state is RSStateGetter && state.getter is RSGetterVbus) {
            final canId = state.canId;
            final voltage = (state.getter as RSGetterVbus).value;
            // canId 1-3 → leg joints, canId 4 → foot
            final idx = canId <= 3 ? legId * 3 + (canId - 1) : 12 + legId;
            if (idx >= 0 && idx < 16) voltages[idx] = voltage;
          }
        }),
      );
    }

    // 发送 getter 请求
    for (int legId = 0; legId < 4; legId++) {
      for (int canId = 1; canId <= 4; canId++) {
        pcans[legId].add(RSEvent.get(canId, key: RSKey.vbus));
      }
    }

    await Future<void>.delayed(timeout);

    for (final s in legSubs) {
      await s.cancel();
    }

    return voltages;
  }

  // ──────────────────────────────────────────────────────────────────────────

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _log.info('RealJoint disposing');
    for (final sub in subscriptions) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _reportController.close();
    _motorFaultController.close();
    _fullFaultController.close();
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
