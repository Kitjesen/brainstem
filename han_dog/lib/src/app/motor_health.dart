import 'dart:async';

import 'package:logging/logging.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

import 'package:han_dog/src/real_joint.dart';

final _log = Logger('han_dog.motor_health');

// ─── Joint layout constants ─────────────────────────────────────────────────

const jointCount = 16;
const footJointIndices = {12, 13, 14, 15};

const jointNames = [
  'FR Hip',
  'FR Thigh',
  'FR Calf',
  'FL Hip',
  'FL Thigh',
  'FL Calf',
  'RR Hip',
  'RR Thigh',
  'RR Calf',
  'RL Hip',
  'RL Thigh',
  'RL Calf',
  'FR Foot',
  'FL Foot',
  'RR Foot',
  'RL Foot',
];

// ─── Severity classification ────────────────────────────────────────────────

enum MotorSeverity { healthy, transient, degraded, critical }

/// Errors that are always critical regardless of streak count.
const _criticalErrors = {
  RSError.driverFault,
  RSError.magneticEncoderFault,
  RSError.underVoltage,
  RSError.overVoltage,
};

/// Errors that start as transient and escalate to degraded after streak.
const _degradableErrors = {RSError.overTemperature, RSError.stallOverload};

const _degradedStreakThreshold = 3;
const _criticalStreakThreshold = 3;
const _maxSimultaneousDegraded = 2;

// ─── Per-joint health state ─────────────────────────────────────────────────

class _JointHealth {
  MotorSeverity severity = MotorSeverity.healthy;
  Set<RSError> lastErrors = {};
  int streak = 0;
  bool needsRecovery = false;

  void reset() {
    severity = MotorSeverity.healthy;
    lastErrors = {};
    streak = 0;
    needsRecovery = false;
  }
}

// ─── Health event for logging/telemetry ─────────────────────────────────────

class MotorHealthEvent {
  final int jointIndex;
  final String jointName;
  final MotorSeverity severity;
  final Set<RSError> errors;
  final int errorBits;
  final RSStatus status;
  final double position;
  final double velocity;
  final double torque;
  final double temperature;
  final int streak;

  const MotorHealthEvent({
    required this.jointIndex,
    required this.jointName,
    required this.severity,
    required this.errors,
    required this.errorBits,
    required this.status,
    required this.position,
    required this.velocity,
    required this.torque,
    required this.temperature,
    required this.streak,
  });

  @override
  String toString() =>
      'MotorHealthEvent($jointName, $severity, $errors, '
      'errorBits=0x${errorBits.toRadixString(16)}, status=$status, '
      'pos=${position.toStringAsFixed(3)}, '
      'vel=${velocity.toStringAsFixed(3)}, '
      'torque=${torque.toStringAsFixed(3)}, '
      'temp=${temperature.toStringAsFixed(1)}°C, streak=$streak)';
}

// ─── MotorHealthManager ─────────────────────────────────────────────────────

class MotorHealthManager {
  final RealJoint _joint;
  final void Function(String reason) _requestFault;

  final _joints = List.generate(jointCount, (_) => _JointHealth());
  final _latestRaw = List<MotorFaultEvent?>.filled(jointCount, null);
  final _healthController = StreamController<MotorHealthEvent>.broadcast();
  StreamSubscription<MotorFaultEvent>? _faultSub;

  MotorHealthManager({
    required RealJoint joint,
    required void Function(String reason) requestFault,
  }) : _joint = joint,
       _requestFault = requestFault {
    _faultSub = joint.motorFaultStream.listen(_onFaultEvent);
  }

  Stream<MotorHealthEvent> get healthStream => _healthController.stream;

  Set<int> get degradedJoints => {
    for (var i = 0; i < jointCount; i++)
      if (_joints[i].severity == MotorSeverity.degraded) i,
  };

  Set<int> get criticalJoints => {
    for (var i = 0; i < jointCount; i++)
      if (_joints[i].severity == MotorSeverity.critical) i,
  };

  bool get hasFaults => _joints.any((j) => j.needsRecovery);

  // ─── Core classification logic ──────────────────────────────────────────

  void _onFaultEvent(MotorFaultEvent event) {
    _latestRaw[event.jointIndex] = event;
    final jh = _joints[event.jointIndex];
    final errs = event.errors;

    if (errs.isEmpty) {
      if (jh.severity != MotorSeverity.healthy) {
        jh.severity = MotorSeverity.healthy;
        jh.streak = 0;
        jh.lastErrors = {};
        _emit(event.jointIndex, jh, event.temperature, raw: event);
      }
      return;
    }

    jh.streak++;
    jh.lastErrors = errs;

    final hasCriticalError = errs.any(_criticalErrors.contains);
    final hasDegradableError = errs.any(_degradableErrors.contains);

    final MotorSeverity newSeverity;

    if (hasCriticalError && jh.streak >= _criticalStreakThreshold) {
      newSeverity = MotorSeverity.critical;
    } else if (hasDegradableError && jh.streak >= _degradedStreakThreshold) {
      newSeverity = MotorSeverity.degraded;
    } else if (jh.streak == 1) {
      newSeverity = MotorSeverity.transient;
    } else {
      newSeverity = jh.severity;
    }

    if (newSeverity != jh.severity || jh.streak == 1) {
      jh.severity = newSeverity;
      _emit(event.jointIndex, jh, event.temperature, raw: event);
    }

    if (newSeverity == MotorSeverity.degraded ||
        newSeverity == MotorSeverity.critical) {
      jh.needsRecovery = true;
    }

    // Escalate: 2+ degraded motors simultaneously → critical for all of them
    if (degradedJoints.length >= _maxSimultaneousDegraded) {
      for (final idx in degradedJoints) {
        final j = _joints[idx];
        if (j.severity != MotorSeverity.critical) {
          j.severity = MotorSeverity.critical;
          j.needsRecovery = true;
          final raw = _latestRaw[idx];
          _emit(idx, j, raw?.temperature ?? 0, raw: raw);
        }
      }
    }

    // Trigger CMS Fault if any joint reached critical
    if (criticalJoints.isNotEmpty) {
      final names = criticalJoints.map((i) => jointNames[i]).join(', ');
      _requestFault('Motor critical fault: $names');
    }
  }

  void _emit(
    int jointIndex,
    _JointHealth jh,
    double temperature, {
    MotorFaultEvent? raw,
  }) {
    final event = MotorHealthEvent(
      jointIndex: jointIndex,
      jointName: jointNames[jointIndex],
      severity: jh.severity,
      errors: jh.lastErrors,
      errorBits: raw?.errorBits ?? 0,
      status: raw?.status ?? RSStatus.reset,
      position: raw?.position ?? 0,
      velocity: raw?.velocity ?? 0,
      torque: raw?.torque ?? 0,
      temperature: temperature,
      streak: jh.streak,
    );
    _healthController.add(event);
  }

  // ─── Action gating ─────────────────────────────────────────────────────

  /// Replace faulted joints' commands with safe values.
  /// Position joints → current measured position (hold still).
  /// Velocity joints (foot) → zero.
  JointsMatrix gateAction(JointsMatrix action, JointsMatrix currentPosition) {
    final gated = degradedJoints.union(criticalJoints);
    if (gated.isEmpty) return action;

    final values = List<double>.from(action.values);
    for (final idx in gated) {
      if (footJointIndices.contains(idx)) {
        values[idx] = 0.0;
      } else {
        values[idx] = currentPosition.values[idx];
      }
    }
    return JointsMatrix.fromList(values);
  }

  // ─── Recovery (call only when Grounded) ─────────────────────────────────

  Future<void> recoverFaults() async {
    final toRecover = <int>[
      for (var i = 0; i < jointCount; i++)
        if (_joints[i].needsRecovery) i,
    ];
    if (toRecover.isEmpty) return;

    _log.info(
      'Recovering ${toRecover.length} faulted motors: '
      '${toRecover.map((i) => jointNames[i]).join(", ")}',
    );

    for (final idx in toRecover) {
      // Skip offline motors — CAN communication lost, clearing is pointless
      if (!_joint.isOnline(idx)) {
        _log.warning(
          'Motor ${jointNames[idx]} is OFFLINE (0 Hz) — skipping recovery, '
          'check CAN cable / power',
        );
        continue;
      }

      var cleared = false;
      for (var attempt = 1; attempt <= 3; attempt++) {
        _joint.clearFaultSingle(idx);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Check if the next report frame shows no errors
        // getReport returns null if motor went offline during recovery
        final report = _joint.getReport(idx);
        if (report == null) {
          _log.warning(
            'Motor ${jointNames[idx]} went offline during recovery attempt $attempt',
          );
          break;
        }
        if (report.errors.errors.isEmpty) {
          _log.info('Motor ${jointNames[idx]} recovered (attempt $attempt)');
          _joints[idx].reset();
          cleared = true;
          break;
        }
        _log.warning(
          'Motor ${jointNames[idx]} still faulted after attempt $attempt '
          '(errors: ${report.errors.errors})',
        );
      }
      if (!cleared) {
        _log.severe(
          'Motor ${jointNames[idx]} recovery FAILED — '
          '${_joint.isOnline(idx) ? "persistent fault" : "went offline"}',
        );
      }
    }
  }

  void dispose() {
    _faultSub?.cancel();
    _healthController.close();
  }
}
