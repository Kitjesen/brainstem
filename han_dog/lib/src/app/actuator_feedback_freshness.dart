import '../yunzhuo_control_mode.dart';

/// Number of actuator report slots emitted by [RealJoint.reportStream].
const hanDogActuatorCount = 16;

/// Maximum age of a motor report that may be used to admit arm operation.
///
/// The hardware normally reports at about 90 Hz. 250 ms tolerates short
/// scheduler stalls while still revoking the 50 Hz arm bridge promptly when a
/// motor or a whole CAN leg disappears.
const defaultActuatorFeedbackMaxAge = Duration(milliseconds: 250);

/// Fail-closed freshness gate for all 16 machine-dog actuator reports.
///
/// This is deliberately independent from motor fault-bit handling: a silent
/// motor cannot publish a healthy or faulty report, so fault state alone cannot
/// prove that all actuators are online. A slot is ready only after it has been
/// observed and while its most recent report is no older than [maxAge].
class ActuatorFeedbackFreshness {
  final Duration maxAge;
  final DateTime Function() _clock;
  final List<DateTime?> _lastReports = List<DateTime?>.filled(
    hanDogActuatorCount,
    null,
  );

  DateTime? _lastClockReading;

  ActuatorFeedbackFreshness({
    this.maxAge = defaultActuatorFeedbackMaxAge,
    DateTime Function()? clock,
  }) : _clock = clock ?? processMonotonicNow {
    if (maxAge <= Duration.zero) {
      throw ArgumentError.value(maxAge, 'maxAge', 'must be positive');
    }
  }

  /// Records one fresh report slot.
  ///
  /// [actuatorIndex] is the 0-based report slot from [RealJoint.reportStream],
  /// not a CAN target id. Invalid ids are ignored and can never make the gate
  /// ready.
  void record(int actuatorIndex) {
    if (actuatorIndex < 0 || actuatorIndex >= hanDogActuatorCount) return;
    final now = _readClock();
    _lastReports[actuatorIndex] = now;
  }

  /// True only when every actuator has a report in the current freshness
  /// window.
  bool get allFresh => unavailableActuatorIndices.isEmpty;

  /// Missing and stale report slots, useful for diagnostics and tests.
  List<int> get unavailableActuatorIndices {
    final now = _readClock();
    return <int>[
      for (var index = 0; index < _lastReports.length; index++)
        if (!_isFresh(_lastReports[index], now)) index,
    ];
  }

  DateTime _readClock() {
    final now = _clock();
    final previous = _lastClockReading;
    if (previous != null && now.isBefore(previous)) {
      // A rollback invalidates every timestamp. Recovery requires a fresh
      // complete set of 16 reports; silently retaining future timestamps would
      // make readiness ambiguous.
      for (var index = 0; index < _lastReports.length; index++) {
        _lastReports[index] = null;
      }
    }
    _lastClockReading = now;
    return now;
  }

  bool _isFresh(DateTime? receivedAt, DateTime now) {
    if (receivedAt == null || receivedAt.isAfter(now)) return false;
    return now.difference(receivedAt) <= maxAge;
  }
}
