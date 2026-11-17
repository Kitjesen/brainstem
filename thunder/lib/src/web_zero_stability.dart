import 'dart:collection';

import 'yunzhuo_control_mode.dart' show processMonotonicNow;

/// Only this exception proves that no calibration write was attempted.
class ZeroNotStarted implements Exception {
  final String reason;
  const ZeroNotStarted(this.reason);
  @override
  String toString() => '尚未写入零点：$reason';
}

typedef _ZeroSample = ({DateTime at, double position, double velocity});

class ZeroStabilityWindow {
  final Duration window;
  final DateTime Function() _clock;
  final _samples = List.generate(16, (_) => ListQueue<_ZeroSample>());
  DateTime? _lastClock;
  static const maximumGap = Duration(milliseconds: 100);
  static const maximumPositionRange = 0.003;
  static const maximumMeanVelocity = 0.1;

  ZeroStabilityWindow({
    this.window = const Duration(milliseconds: 500),
    DateTime Function()? clock,
  }) : _clock = clock ?? processMonotonicNow {
    if (window <= Duration.zero) throw ArgumentError('Invalid zero window');
  }

  void clear() {
    for (final samples in _samples) {
      samples.clear();
    }
    _lastClock = null;
  }

  DateTime _readClock() {
    final at = _clock();
    if (_lastClock != null && at.isBefore(_lastClock!)) clear();
    _lastClock = at;
    return at;
  }

  void _prune(ListQueue<_ZeroSample> samples, DateTime at) {
    final cutoff = at.subtract(window);
    // Retain one boundary sample so readiness cannot mature from cached data.
    while (samples.length > 1 && !samples.elementAt(1).at.isAfter(cutoff)) {
      samples.removeFirst();
    }
  }

  /// Index is CAN report order: FR/FL/RR/RL, each Hip/Thigh/Calf/Foot.
  void record(
    int id, {
    required double position,
    required double velocity,
    bool healthy = true,
  }) {
    if (id < 0 || id >= 16) return;
    final at = _readClock();
    final samples = _samples[id];
    if (!healthy || !position.isFinite || !velocity.isFinite) {
      samples.clear();
      return;
    }
    if (samples.isNotEmpty && at.difference(samples.last.at) > maximumGap) {
      samples.clear();
    }
    if (samples.isNotEmpty && samples.last.at == at) samples.removeLast();
    samples.add((at: at, position: position, velocity: velocity));
    _prune(samples, at);
  }

  String? blockReason() {
    final at = _readClock();
    for (var id = 0; id < 16; id++) {
      final samples = _samples[id];
      // The window ends at the latest report, not at an arbitrary UI query.
      final name =
          '${['FR', 'FL', 'RR', 'RL'][id ~/ 4]} '
          '${['Hip', 'Thigh', 'Calf', 'Foot'][id % 4]}';
      if (samples.length < 3 ||
          at.difference(samples.last.at) > maximumGap ||
          samples.last.at.difference(samples.first.at) < window) {
        return '等待连续${window.inMilliseconds}ms静止反馈：$name';
      }
      var low = samples.first.position;
      var high = low;
      var velocitySum = 0.0;
      for (final sample in samples) {
        if (sample.position < low) low = sample.position;
        if (sample.position > high) high = sample.position;
        velocitySum += sample.velocity;
      }
      if (high - low > maximumPositionRange ||
          (velocitySum / samples.length).abs() > maximumMeanVelocity) {
        return '等待关节稳定：$name';
      }
    }
    return null;
  }
}
