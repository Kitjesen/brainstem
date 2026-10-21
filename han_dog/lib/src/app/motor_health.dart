import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

import 'package:han_dog/src/real_joint.dart';

final _log = Logger('han_dog.motor_health');

// ─── Joint layout constants ─────────────────────────────────────────────────

const jointCount = 16;
const footJointIndices = {12, 13, 14, 15};
const hipJointIndices = [0, 3, 6, 9];

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

const _diagnosticSamplePeriodUs = 50000; // 20 Hz maximum per motor
const _diagnosticWindowSamples = 50; // 2.5 seconds at 20 Hz
const _controlSamplePeriodUs = 10000; // 100 Hz maximum
const _controlWindowSamples = 275; // 2.75 seconds at 100 Hz
const _faultPreWindowUs = 2000000;
const _faultPostWindowUs = 500000;
const _sameJointCaptureCooldownUs = 5000000;
const _largeHipErrorRad = 0.15;

class _DiagnosticSample {
  final int monotonicUs;
  final int maxFeedbackGapUs;
  final double position;
  final double velocity;
  final double torque;
  final double temperature;
  final int errorBits;

  const _DiagnosticSample({
    required this.monotonicUs,
    required this.maxFeedbackGapUs,
    required this.position,
    required this.velocity,
    required this.torque,
    required this.temperature,
    required this.errorBits,
  });

  Map<String, Object> toJson(int jointIndex, int wallClockUs) => {
    'type': 'sample',
    'time': DateTime.fromMicrosecondsSinceEpoch(wallClockUs).toIso8601String(),
    'jointIndex': jointIndex,
    'jointName': jointNames[jointIndex],
    'position': position,
    'velocity': velocity,
    'torque': torque,
    'temperature': temperature,
    'errorBits': '0x${errorBits.toRadixString(16)}',
    'maxFeedbackGapUs': maxFeedbackGapUs,
  };
}

class _ControlSample {
  final int monotonicUs;
  final String cmsState;
  final bool motorOutputEnabled;
  final List<double?> command;
  final List<double?> policyHipTarget;
  final List<double?> sentHipTarget;
  final List<double?> hipPosition;
  final List<double?> hipError;
  final List<double?> hipVelocity;
  final List<double?> hipTorque;
  final List<double?> hipTargetStep;
  final List<double?> gyroscope;
  final int inferenceUs;

  const _ControlSample({
    required this.monotonicUs,
    required this.cmsState,
    required this.motorOutputEnabled,
    required this.command,
    required this.policyHipTarget,
    required this.sentHipTarget,
    required this.hipPosition,
    required this.hipError,
    required this.hipVelocity,
    required this.hipTorque,
    required this.hipTargetStep,
    required this.gyroscope,
    required this.inferenceUs,
  });

  Map<String, Object?> toJson(int wallClockUs) => {
    'type': 'control',
    'time': DateTime.fromMicrosecondsSinceEpoch(wallClockUs).toIso8601String(),
    'cmsState': cmsState,
    'motorOutputEnabled': motorOutputEnabled,
    'command': command,
    'policyHipTarget': policyHipTarget,
    'sentHipTarget': sentHipTarget,
    'hipPosition': hipPosition,
    'hipError': hipError,
    'hipVelocity': hipVelocity,
    'hipTorque': hipTorque,
    'hipTargetStep': hipTargetStep,
    'gyroscope': gyroscope,
    'inferenceUs': inferenceUs,
  };
}

// ─── Severity classification ────────────────────────────────────────────────

enum MotorSeverity { healthy, transient, degraded, critical }

/// Errors that are always critical regardless of streak count.
const _criticalErrors = {
  RSError.driverFault,
  RSError.threePhaseCurrentFault,
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
      'pos=${position.toStringAsFixed(3)}, vel=${velocity.toStringAsFixed(3)}, '
      'torque=${torque.toStringAsFixed(3)}, temp=${temperature.toStringAsFixed(1)}C, '
      'streak=$streak)';
}

// ??? MotorHealthManager ?????????????????????????????????????????????????????

class MotorHealthManager {
  final RealJoint _joint;
  final void Function(String reason) _requestFault;
  final Map<String, Object?> Function()? _contextProvider;
  final String _faultLogDirectory;

  final _joints = List.generate(jointCount, (_) => _JointHealth());
  final _healthController = StreamController<MotorHealthEvent>.broadcast();
  StreamSubscription<MotorFaultEvent>? _faultSub;
  StreamSubscription<MotorFullFaultEvent>? _fullFaultSub;
  final _clock = Stopwatch()..start();
  late final int _wallClockAnchorUs = DateTime.now().microsecondsSinceEpoch;
  final _samples = List.generate(
    jointCount,
    (_) => ListQueue<_DiagnosticSample>(_diagnosticWindowSamples),
  );
  final _controlSamples = ListQueue<_ControlSample>(_controlWindowSamples);
  int _lastControlSampleUs = 0;
  List<double?>? _lastSentHipTarget;
  final _lastReportUs = List<int>.filled(jointCount, 0);
  final _lastSampleUs = List<int>.filled(jointCount, 0);
  final _maxGapSinceSampleUs = List<int>.filled(jointCount, 0);
  final _latestFullFault =
      <int, (int bits, Set<RSError> errors, int monotonicUs)>{};
  final _capturesInFlight = <int>{};
  final _lastCaptureUs = List<int>.filled(jointCount, -10000000);
  bool _recoveryInProgress = false;
  int _nextFaultId = 1;

  MotorHealthManager({
    required RealJoint joint,
    required void Function(String reason) requestFault,
    Map<String, Object?> Function()? contextProvider,
    String faultLogDirectory = 'logs/motor_fault_events',
  }) : _joint = joint,
       _requestFault = requestFault,
       _contextProvider = contextProvider,
       _faultLogDirectory = faultLogDirectory {
    _faultSub = joint.motorFaultStream.listen(_onFaultEvent);
    _fullFaultSub = joint.fullFaultStream.listen((event) {
      _latestFullFault[event.jointIndex] = (
        event.faultBits,
        event.decodedErrors,
        _clock.elapsedMicroseconds,
      );
    });
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

  /// Records the Hip control chain in memory at up to 100 Hz. Nothing is
  /// written during healthy operation; the ring is flushed only on a fault.
  void recordControlSample({
    required String cmsState,
    required bool motorOutputEnabled,
    required List<double> command,
    required JointsMatrix policyTarget,
    required JointsMatrix sentTarget,
    required JointsMatrix position,
    required JointsMatrix velocity,
    required List<double?> hipTorque,
    required List<double> gyroscope,
    required int inferenceUs,
  }) {
    final nowUs = _clock.elapsedMicroseconds;
    if (nowUs - _lastControlSampleUs < _controlSamplePeriodUs) return;
    _lastControlSampleUs = nowUs;

    List<double?> hipValues(JointsMatrix source) => [
      for (final index in hipJointIndices) _finite(source.values[index]),
    ];

    final policy = hipValues(policyTarget);
    final sent = hipValues(sentTarget);
    final actual = hipValues(position);
    final speed = hipValues(velocity);
    final error = List<double?>.generate(4, (i) {
      final target = sent[i];
      final measured = actual[i];
      return target == null || measured == null ? null : target - measured;
    });
    final previous = _lastSentHipTarget;
    final step = List<double?>.generate(4, (i) {
      final target = sent[i];
      final old = previous?[i];
      return target == null || old == null ? null : target - old;
    });
    _lastSentHipTarget = List<double?>.from(sent);

    if (_controlSamples.length == _controlWindowSamples) {
      _controlSamples.removeFirst();
    }
    _controlSamples.addLast(
      _ControlSample(
        monotonicUs: nowUs,
        cmsState: cmsState,
        motorOutputEnabled: motorOutputEnabled,
        command: command.map(_finite).toList(growable: false),
        policyHipTarget: policy,
        sentHipTarget: sent,
        hipPosition: actual,
        hipError: error,
        hipVelocity: speed,
        hipTorque: hipTorque.map(_finiteNullable).toList(growable: false),
        hipTargetStep: step,
        gyroscope: gyroscope.map(_finite).toList(growable: false),
        inferenceUs: inferenceUs,
      ),
    );
  }

  static double? _finite(double value) => value.isFinite ? value : null;
  static double? _finiteNullable(double? value) =>
      value != null && value.isFinite ? value : null;

  // ─── Core classification logic ──────────────────────────────────────────

  void _recordSample(MotorFaultEvent event) {
    final jointIndex = event.jointIndex;
    final nowUs = _clock.elapsedMicroseconds;
    final previousUs = _lastReportUs[jointIndex];
    _lastReportUs[jointIndex] = nowUs;
    if (previousUs != 0) {
      final gapUs = nowUs - previousUs;
      if (gapUs > _maxGapSinceSampleUs[jointIndex]) {
        _maxGapSinceSampleUs[jointIndex] = gapUs;
      }
    }
    if (nowUs - _lastSampleUs[jointIndex] < _diagnosticSamplePeriodUs) {
      return;
    }
    _lastSampleUs[jointIndex] = nowUs;
    final queue = _samples[jointIndex];
    if (queue.length == _diagnosticWindowSamples) queue.removeFirst();
    queue.addLast(
      _DiagnosticSample(
        monotonicUs: nowUs,
        maxFeedbackGapUs: _maxGapSinceSampleUs[jointIndex],
        position: event.position,
        velocity: event.velocity,
        torque: event.torque,
        temperature: event.temperature,
        errorBits: event.errorBits,
      ),
    );
    _maxGapSinceSampleUs[jointIndex] = 0;
  }

  void _onFaultEvent(MotorFaultEvent event) {
    _recordSample(event);
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

    if (jh.streak == 0) {
      unawaited(_captureFault(event));
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
          _emit(idx, j, 0);
        }
      }
    }

    // Trigger CMS Fault if any joint reached critical
    if (criticalJoints.isNotEmpty) {
      final names = criticalJoints.map((i) => jointNames[i]).join(', ');
      _requestFault('Motor critical fault: $names');
    }
  }

  Future<void> _captureFault(MotorFaultEvent event) async {
    final jointIndex = event.jointIndex;
    final triggerUs = _clock.elapsedMicroseconds;
    if (_capturesInFlight.contains(jointIndex) ||
        triggerUs - _lastCaptureUs[jointIndex] < _sameJointCaptureCooldownUs) {
      return;
    }
    _capturesInFlight.add(jointIndex);
    _lastCaptureUs[jointIndex] = triggerUs;
    final faultId = _nextFaultId++;
    final diagnosticsFuture = _joint.readFaultDiagnostics(jointIndex);
    final triggerContext = <String, Object?>{};
    try {
      triggerContext.addAll(_contextProvider?.call() ?? const {});
    } catch (error) {
      triggerContext['contextError'] = error.toString();
    }

    try {
      await Future<void>.delayed(
        const Duration(microseconds: _faultPostWindowUs),
      );
      Map<String, double> diagnostics;
      try {
        diagnostics = await diagnosticsFuture;
      } catch (error) {
        diagnostics = {};
        _log.warning(
          'FAULT_SNAPSHOT id=$faultId diagnostic read failed: $error',
        );
      }

      final triggerWallUs = _wallClockAnchorUs + triggerUs;
      final fullFault = _latestFullFault[jointIndex];
      final matchingFullFault =
          fullFault != null && (fullFault.$3 - triggerUs).abs() <= 1000000
          ? fullFault
          : null;
      final windowStartUs = triggerUs - _faultPreWindowUs;
      final windowEndUs = triggerUs + _faultPostWindowUs;
      final controlWindow = _controlSamples
          .where(
            (sample) =>
                sample.monotonicUs >= windowStartUs &&
                sample.monotonicUs <= windowEndUs,
          )
          .toList(growable: false);
      final activeHipKd = [
        for (final index in hipJointIndices) _joint.kdExt.values[index],
      ];
      final lines = <String>[
        jsonEncode({
          'type': 'fault',
          'faultId': faultId,
          'time': DateTime.fromMicrosecondsSinceEpoch(
            triggerWallUs,
          ).toIso8601String(),
          'jointIndex': jointIndex,
          'jointName': jointNames[jointIndex],
          'compressedErrorBits': '0x${event.errorBits.toRadixString(16)}',
          'errors': event.errors.map((e) => e.name).toList(),
          'status': event.status.value,
          'position': event.position,
          'velocity': event.velocity,
          'torque': event.torque,
          'temperature': event.temperature,
          if (matchingFullFault != null) ...{
            'fullFaultBits': '0x${matchingFullFault.$1.toRadixString(16)}',
            'fullFaultErrors': matchingFullFault.$2
                .map((error) => error.name)
                .toList(),
          },
          'diagnostics': diagnostics,
          'context': triggerContext,
          'hipKd': {
            'walkingScale': hanDogWalkingHipKdScale,
            'active': activeHipKd,
          },
          'hipTrackingSummary': _buildHipTrackingSummary(
            controlWindow,
            triggerUs,
          ),
        }),
      ];
      for (final sample in controlWindow) {
        lines.add(
          jsonEncode(sample.toJson(_wallClockAnchorUs + sample.monotonicUs)),
        );
      }
      var feedbackSampleCount = 0;
      for (var i = 0; i < jointCount; i++) {
        for (final sample in _samples[i]) {
          if (sample.monotonicUs < windowStartUs ||
              sample.monotonicUs > windowEndUs) {
            continue;
          }
          lines.add(
            jsonEncode(
              sample.toJson(i, _wallClockAnchorUs + sample.monotonicUs),
            ),
          );
          feedbackSampleCount++;
        }
      }

      final directory = Directory(_faultLogDirectory);
      await directory.create(recursive: true);
      final stamp = DateTime.fromMicrosecondsSinceEpoch(
        triggerWallUs,
      ).toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final safeJoint = jointNames[jointIndex].replaceAll(' ', '_');
      final file = File(
        '${directory.path}/motor_fault_${stamp}_${safeJoint}_$faultId.jsonl',
      );
      await file.writeAsString('${lines.join('\n')}\n', flush: true);
      _log.severe(
        'FAULT_SNAPSHOT id=$faultId joint=${jointNames[jointIndex]} '
        'controlSamples=${controlWindow.length} '
        'feedbackSamples=$feedbackSampleCount file=${file.path}',
      );
    } catch (error, stackTrace) {
      _log.severe('FAULT_SNAPSHOT id=$faultId write failed', error, stackTrace);
    } finally {
      _capturesInFlight.remove(jointIndex);
    }
  }

  Map<String, Object?> _buildHipTrackingSummary(
    List<_ControlSample> samples,
    int triggerUs,
  ) {
    final perHip = <String, Object?>{};
    for (var hip = 0; hip < hipJointIndices.length; hip++) {
      _ControlSample? triggerSample;
      _ControlSample? maxErrorSample;
      var maxAbsError = 0.0;
      var maxAbsTorque = 0.0;
      var maxAbsVelocity = 0.0;
      var maxAbsTargetStep = 0.0;
      int? largeErrorRunStartUs;
      int? previousLargeErrorUs;
      var longestLargeErrorUs = 0;

      for (final sample in samples) {
        if (sample.monotonicUs <= triggerUs &&
            (triggerSample == null ||
                sample.monotonicUs > triggerSample.monotonicUs)) {
          triggerSample = sample;
        }
        final error = sample.hipError[hip];
        if (error != null && error.abs() >= maxAbsError) {
          maxAbsError = error.abs();
          maxErrorSample = sample;
        }
        final torque = sample.hipTorque[hip];
        if (torque != null && torque.abs() > maxAbsTorque) {
          maxAbsTorque = torque.abs();
        }
        final velocity = sample.hipVelocity[hip];
        if (velocity != null && velocity.abs() > maxAbsVelocity) {
          maxAbsVelocity = velocity.abs();
        }
        final targetStep = sample.hipTargetStep[hip];
        if (targetStep != null && targetStep.abs() > maxAbsTargetStep) {
          maxAbsTargetStep = targetStep.abs();
        }

        if (error != null && error.abs() >= _largeHipErrorRad) {
          if (largeErrorRunStartUs == null ||
              previousLargeErrorUs == null ||
              sample.monotonicUs - previousLargeErrorUs > 30000) {
            largeErrorRunStartUs = sample.monotonicUs;
          }
          previousLargeErrorUs = sample.monotonicUs;
          final durationUs =
              sample.monotonicUs -
              largeErrorRunStartUs +
              _controlSamplePeriodUs;
          if (durationUs > longestLargeErrorUs) {
            longestLargeErrorUs = durationUs;
          }
        } else {
          largeErrorRunStartUs = null;
          previousLargeErrorUs = null;
        }
      }

      perHip[jointNames[hipJointIndices[hip]]] = {
        'errorAtTriggerRad': triggerSample?.hipError[hip],
        'targetAtTriggerRad': triggerSample?.sentHipTarget[hip],
        'positionAtTriggerRad': triggerSample?.hipPosition[hip],
        'torqueAtTriggerNm': triggerSample?.hipTorque[hip],
        'maxAbsErrorRad': maxAbsError,
        'maxAbsErrorRelativeMs': maxErrorSample == null
            ? null
            : (maxErrorSample.monotonicUs - triggerUs) / 1000.0,
        'commandAtMaxError': maxErrorSample?.command,
        'maxAbsTorqueNm': maxAbsTorque,
        'maxAbsVelocityRadS': maxAbsVelocity,
        'maxAbsTargetStepRad': maxAbsTargetStep,
        'largeErrorThresholdRad': _largeHipErrorRad,
        'longestLargeErrorMs': longestLargeErrorUs / 1000.0,
      };
    }
    return {'sampleRateHz': 100, 'perHip': perHip};
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
      status: raw?.status ?? RSStatus.fromValue(0),
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
    if (_recoveryInProgress) return;
    _recoveryInProgress = true;
    try {
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
    } finally {
      _recoveryInProgress = false;
    }
  }

  void dispose() {
    _faultSub?.cancel();
    _fullFaultSub?.cancel();
    _healthController.close();
  }
}
