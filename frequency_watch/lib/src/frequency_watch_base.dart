import 'stats.dart';

class FrequencyWatch {
  final int windowSize;
  final List<int> _timestamps = [];
  final Stopwatch _stopwatch = Stopwatch()..start();

  FrequencyWatch({this.windowSize = 100});

  void watch() {
    final now = _stopwatch.elapsedMicroseconds;
    _timestamps.add(now);
    if (_timestamps.length > windowSize) {
      _timestamps.removeAt(0);
    }
  }

  void reset() {
    _timestamps.clear();
    _stopwatch.reset();
    _stopwatch.start();
  }

  FrequencyStats get current {
    if (_timestamps.length < 2) return FrequencyStats.zero();

    final intervals = <int>[];
    for (int i = 1; i < _timestamps.length; i++) {
      intervals.add(_timestamps[i] - _timestamps[i - 1]);
    }

    intervals.sort();
    final min = intervals.first;
    final max = intervals.last;
    final median = intervals[intervals.length ~/ 2];
    final p95 = intervals[(intervals.length * 95 ~/ 100)];
    final avg = intervals.reduce((a, b) => a + b) ~/ intervals.length;

    return FrequencyStats(
      count: _timestamps.length,
      min: min,
      max: max,
      median: median,
      p95: p95,
      avg: avg,
      medianHz: median > 0 ? 1e6 / median : 0.0,
      p95Hz: p95 > 0 ? 1e6 / p95 : 0.0,
      avgHz: avg > 0 ? 1e6 / avg : 0.0,
    );
  }

  @override
  String toString() {
    return current.toString();
  }
}
