import 'dart:async';
import 'dart:math' as math;

enum RecoveryPhase {
  disabled,
  preparing,
  waiting,
  recovering,
  balanced,
  lowering,
  proneHold,
  standUp,
  standing,
  sitDown,
  grounded,
  failed,
}

class RecoverySample {
  final List<double> angular, gravity, q, dq;
  final int ageMs;
  final bool healthy;
  RecoverySample({
    required List<double> angular,
    required List<double> gravity,
    required List<double> q,
    required List<double> dq,
    required this.ageMs,
    required this.healthy,
  }) : angular = List.unmodifiable(angular),
       gravity = List.unmodifiable(gravity),
       q = List.unmodifiable(q),
       dq = List.unmodifiable(dq);

  void validate() {
    if (angular.length != 3 ||
        gravity.length != 3 ||
        q.length != 16 ||
        dq.length != 16 ||
        ![...angular, ...gravity, ...q, ...dq].every((v) => v.isFinite) ||
        !healthy ||
        ageMs < 0 ||
        ageMs > 100) {
      throw StateError('Recovery requires fresh, finite and healthy feedback');
    }
    final norm = math.sqrt(gravity.fold(0.0, (s, v) => s + v * v));
    if ((norm - 1).abs() > .1) throw StateError('Invalid projected gravity');
  }

  bool get upright =>
      -gravity[2] >= .94 &&
      angular.fold(0.0, (s, v) => s + v * v) <= .2 * .2 &&
      dq.take(12).every((v) => v.abs() <= .5) &&
      dq.skip(12).every((v) => v.abs() <= 1);
}

class RecoveryFrame {
  final List<double> target, kp, kd;
  RecoveryFrame(List<double> target, List<double> kp, List<double> kd)
    : target = List.unmodifiable(target),
      kp = List.unmodifiable(kp),
      kd = List.unmodifiable(kd);

  factory RecoveryFrame.fixed(List<double> target) => RecoveryFrame(
    target,
    [...List.filled(12, 80.0), ...List.filled(4, 0.0)],
    [...List.filled(12, 10.0), ...List.filled(4, 1.0)],
  );
}

/// Used at the last motor-send boundary, not just in the UI/state listener.
class RecoveryGainGuard {
  bool active = false;
  void check(RecoveryFrame frame) {
    if (!active) return;
    if (frame.target.length != 16 ||
        frame.kp.length != 16 ||
        frame.kd.length != 16 ||
        ![...frame.target, ...frame.kp, ...frame.kd].every((v) => v.isFinite)) {
      throw StateError('Recovery rejected invalid motor frame');
    }
    final expected = RecoveryFrame.fixed(frame.target);
    for (var i = 0; i < 16; i++) {
      if ((frame.kp[i] - expected.kp[i]).abs() > 1e-9 ||
          (frame.kd[i] - expected.kd[i]).abs() > 1e-9) {
        throw StateError('Recovery gain isolation violation at joint $i');
      }
    }
  }
}

abstract interface class RecoveryInference {
  Future<void> reset(int epoch);
  Future<List<double>> infer(int epoch, int seq, RecoverySample sample);
}

/// The adapter is local-only until a hardware integration has passed shadow tests.
abstract interface class RecoveryOutput {
  void stage(RecoveryFrame frame);
  void send(RecoveryFrame frame);
  void disable(String reason);
  void standUp();
  void sitDown();
}

class RecoveryController {
  final RecoveryInference inference;
  final RecoveryOutput output;
  final RecoveryGainGuard guard;
  final int Function() nowUs;
  final List<double> lower, upper;
  final List<double> initialLower, initialUpper;
  final bool skipInitialHipBounds;
  final double? legTargetRateRadS;
  RecoveryPhase phase = RecoveryPhase.disabled;
  int _epoch = 0, _seq = 0, _started = 0;
  int? _uprightSince;
  bool _busy = false, _sawR1 = false;
  bool? _lastR1;
  RecoveryFrame? _hold;
  List<double>? _previousLegTarget;
  int? _previousLegTargetUs;
  List<double>? _sittingFrom, _sittingTarget;
  int _sittingStartedUs = 0, _sittingDurationUs = 0;
  String? failure;
  List<double>? get sittingHoldTarget => phase == RecoveryPhase.proneHold
      ? List<double>.unmodifiable(_sittingTarget!)
      : null;
  int get sessionEpoch => _epoch;
  static const nominal = [
    -.1,
    -.8,
    1.8,
    .1,
    .8,
    -1.8,
    .1,
    .8,
    -1.8,
    -.1,
    -.8,
    1.8,
  ];

  RecoveryController({
    required this.inference,
    required this.output,
    required this.guard,
    required this.nowUs,
    required List<double> lower,
    required List<double> upper,
    List<double>? initialLower,
    List<double>? initialUpper,
    this.skipInitialHipBounds = false,
    this.legTargetRateRadS,
  }) : lower = List.unmodifiable(lower),
       upper = List.unmodifiable(upper),
       initialLower = List.unmodifiable(initialLower ?? lower.take(12)),
       initialUpper = List.unmodifiable(initialUpper ?? upper.take(12)) {
    if (legTargetRateRadS != null &&
        (!legTargetRateRadS!.isFinite || legTargetRateRadS! <= 0)) {
      throw ArgumentError('Leg target rate must be finite and positive');
    }
    if (lower.length != 16 || upper.length != 16) {
      throw ArgumentError('Expected 16 hardware limits');
    }
    for (var i = 0; i < 16; i++) {
      if (!lower[i].isFinite || !upper[i].isFinite || lower[i] >= upper[i]) {
        throw ArgumentError('Invalid hardware limits');
      }
    }
    if ((initialLower == null) != (initialUpper == null) ||
        this.initialLower.length != 12 ||
        this.initialUpper.length != 12) {
      throw ArgumentError('Expected both 12-joint initial pose limits');
    }
    for (var i = 0; i < 12; i++) {
      if (!this.initialLower[i].isFinite ||
          !this.initialUpper[i].isFinite ||
          this.initialLower[i] > lower[i] ||
          this.initialUpper[i] < upper[i]) {
        throw ArgumentError('Initial pose limits must contain action limits');
      }
    }
  }

  void _validateInitialPose(RecoverySample sample) {
    sample.validate();
    for (var i = 0; i < 12; i++) {
      // Only initial placement can exceed Hip travel; policy targets stay bounded.
      if (skipInitialHipBounds && i % 3 == 0) continue;
      if (sample.q[i] < initialLower[i] || sample.q[i] > initialUpper[i]) {
        throw StateError('Measured joint $i outside initial pose limits');
      }
    }
  }

  bool get isolatesGains => switch (phase) {
    RecoveryPhase.preparing ||
    RecoveryPhase.waiting ||
    RecoveryPhase.recovering ||
    RecoveryPhase.balanced ||
    RecoveryPhase.lowering ||
    RecoveryPhase.proneHold => true,
    _ => false,
  };

  Future<void> prepareEnable(RecoverySample Function() readSample) async {
    if (phase != RecoveryPhase.disabled && phase != RecoveryPhase.failed) {
      throw StateError('Disable before starting another recovery session');
    }
    final epoch = ++_epoch;
    phase = RecoveryPhase.preparing;
    guard.active = true;
    failure = null;
    _sawR1 = false;
    _lastR1 = null;
    _uprightSince = null;
    _seq = 0;
    _previousLegTarget = null;
    _previousLegTargetUs = null;
    try {
      _validateInitialPose(readSample());
      await inference.reset(epoch).timeout(const Duration(seconds: 2));
      if (epoch != _epoch || phase != RecoveryPhase.preparing) {
        throw StateError('Enable cancelled');
      }
      // Capture after reset so H never uses an older, pre-wait joint pose.
      final sample = readSample();
      _validateInitialPose(sample);
      final hold = RecoveryFrame.fixed([
        ...sample.q.take(12),
        0.0,
        0.0,
        0.0,
        0.0,
      ]);
      _hold = hold;
      guard.check(hold);
      output.stage(hold);
    } catch (error) {
      if (epoch == _epoch) abort('Enable preparation: $error');
      rethrow;
    }
  }

  void enabledConfirmed() {
    if (phase != RecoveryPhase.preparing) {
      throw StateError('Unprepared motor enable');
    }
    phase = RecoveryPhase.waiting;
    // First R1 value after H completion is a baseline, never a trigger.
    _sawR1 = false;
  }

  Future<bool> r1(bool value, RecoverySample sample) async {
    if (phase != RecoveryPhase.waiting) return false;
    if (!_sawR1) {
      _sawR1 = true;
      _lastR1 = value;
      return false;
    }
    if (value == _lastR1) return false;
    _lastR1 = value;
    return trigger(sample);
  }

  Future<bool> trigger(RecoverySample sample) async {
    if (phase != RecoveryPhase.waiting) return false;
    final epoch = ++_epoch;
    phase = RecoveryPhase.preparing;
    try {
      sample.validate();
      await inference.reset(epoch).timeout(const Duration(seconds: 2));
      if (epoch != _epoch || phase != RecoveryPhase.preparing) return false;
      _seq = 0;
      _previousLegTarget = null;
      _previousLegTargetUs = null;
      _started = nowUs();
      _uprightSince = null;
      phase = RecoveryPhase.recovering;
      return true;
    } catch (error) {
      if (epoch == _epoch) abort('Recovery trigger: $error');
      return false;
    }
  }

  Future<void> tick(RecoverySample sample) async {
    if (phase == RecoveryPhase.lowering || phase == RecoveryPhase.proneHold) {
      try {
        sample.validate();
        final t = ((nowUs() - _sittingStartedUs) / _sittingDurationUs).clamp(
          0.0,
          1.0,
        );
        final target = List<double>.generate(
          16,
          (i) => i < 12
              ? _sittingFrom![i] + (_sittingTarget![i] - _sittingFrom![i]) * t
              : 0,
        );
        _sendTarget(target, sample);
        if (phase == RecoveryPhase.lowering &&
            t == 1 &&
            List.generate(
              12,
              (i) => (target[i] - _sittingTarget![i]).abs() <= 1e-9,
            ).every((v) => v)) {
          // Match normal L2 Grounded hold: latch once instead of pushing into the floor.
          _sittingTarget = [...sample.q.take(12), ...List<double>.filled(4, 0)];
          phase = RecoveryPhase.proneHold;
        }
      } catch (error) {
        abort('Recovery sit-down: $error');
      }
      return;
    }
    if (phase == RecoveryPhase.waiting) {
      try {
        sample.validate();
        guard.check(_hold!);
        output.send(_hold!);
      } catch (error) {
        abort('Waiting feedback: $error');
      }
      return;
    }
    if (phase != RecoveryPhase.recovering && phase != RecoveryPhase.balanced) {
      return;
    }
    try {
      sample.validate();
    } catch (e) {
      abort('$e');
      return;
    }
    if (phase == RecoveryPhase.recovering && nowUs() - _started >= 15000000) {
      abort('Recovery exceeded 15 seconds');
      return;
    }
    if (_busy) return;
    _busy = true;
    final epoch = _epoch;
    final seq = _seq++;
    final requestedAt = nowUs();
    try {
      final raw = await inference
          .infer(epoch, seq, sample)
          .timeout(const Duration(milliseconds: 40));
      if (epoch != _epoch ||
          !isolatesGains ||
          (phase != RecoveryPhase.recovering &&
              phase != RecoveryPhase.balanced)) {
        return;
      }
      if (nowUs() - requestedAt > 40000) {
        throw StateError('Late recovery result');
      }
      if (raw.length != 16 || !raw.every((v) => v.isFinite && v.abs() <= 4)) {
        throw StateError('Invalid raw action');
      }
      final target = List<double>.generate(16, (i) {
        final value = i < 12
            ? nominal[i] + raw[i] * (i % 3 == 0 ? .125 : .25)
            : (raw[i] * 5).clamp(-3.0, 3.0);
        return value.clamp(lower[i], upper[i]).toDouble();
      });
      _sendTarget(target, sample);
      if (phase == RecoveryPhase.recovering) {
        if (!sample.upright) {
          _uprightSince = null;
        } else {
          _uprightSince ??= nowUs();
        }
        if (_uprightSince != null && nowUs() - _uprightSince! >= 1000000) {
          phase = RecoveryPhase.balanced;
        }
      }
    } catch (error) {
      if (epoch == _epoch) abort('Recovery inference: $error');
    } finally {
      if (epoch == _epoch) _busy = false;
    }
  }

  void _sendTarget(List<double> target, RecoverySample sample) {
    final rate = legTargetRateRadS;
    if (rate != null) {
      final dt = _previousLegTargetUs == null
          ? .02
          : ((nowUs() - _previousLegTargetUs!) / 1000000).clamp(0.0, .02);
      final previous = _previousLegTarget ?? sample.q;
      final step = rate * dt;
      // Clamp model requests before slew; initial-pose and sit-down bridges stay continuous.
      for (var i = 0; i < 12; i++) {
        target[i] = previous[i] + (target[i] - previous[i]).clamp(-step, step);
      }
    }
    final frame = RecoveryFrame.fixed(target);
    guard.check(frame);
    output.send(frame);
    _previousLegTarget = target.take(12).toList();
    _previousLegTargetUs = nowUs();
  }

  bool lowerToSitting(
    RecoverySample sample,
    List<double> target,
    Duration duration,
  ) {
    if (phase != RecoveryPhase.balanced ||
        duration <= Duration.zero ||
        target.length != 16 ||
        !target.every((v) => v.isFinite) ||
        target.skip(12).any((v) => v != 0)) {
      return false;
    }
    try {
      sample.validate();
    } catch (_) {
      return false;
    }
    if (!sample.upright) return false;
    for (var i = 0; i < 12; i++) {
      if (target[i] < initialLower[i] || target[i] > initialUpper[i]) {
        return false;
      }
    }
    ++_epoch; // Fence a policy result already in flight before replacing its output.
    _busy = false;
    _sittingFrom = List<double>.from(sample.q);
    _sittingTarget = List<double>.from(target);
    _sittingDurationUs = duration.inMicroseconds;
    _sittingStartedUs = nowUs();
    phase = RecoveryPhase.lowering;
    return true;
  }

  bool l1(RecoverySample sample) {
    if (phase != RecoveryPhase.balanced) return false;
    try {
      sample.validate();
    } catch (e) {
      abort('$e');
      return false;
    }
    if (!sample.upright) return false;
    ++_epoch; // Invalidate in-flight 80/10 actions before handing off gains.
    _busy = false;
    phase = RecoveryPhase.standUp;
    guard.active = false;
    try {
      output.standUp();
    } catch (error) {
      abort('Stand-up handover failed: $error');
      return false;
    }
    return true;
  }

  void standUpCompleted() {
    if (phase != RecoveryPhase.standUp) {
      throw StateError('Unexpected stand-up completion');
    }
    phase = RecoveryPhase.standing;
  }

  bool l2() {
    if (phase != RecoveryPhase.standing) return false;
    phase = RecoveryPhase.sitDown;
    try {
      output.sitDown();
    } catch (error) {
      abort('Sit-down handover failed: $error');
      return false;
    }
    return true;
  }

  void sitDownCompleted() {
    if (phase != RecoveryPhase.sitDown) {
      throw StateError('Unexpected sit-down completion');
    }
    phase = RecoveryPhase.grounded;
  }

  void disabled() {
    ++_epoch;
    phase = RecoveryPhase.disabled;
    _busy = false;
    // Keep isolation until the external hardware-disable acknowledgement.
    guard.active = true;
    output.disable('Operator disabled recovery');
  }

  void abort(String reason) {
    ++_epoch;
    _busy = false;
    failure = reason;
    phase = RecoveryPhase.failed;
    guard.active = true;
    output.disable(reason);
  }
}
