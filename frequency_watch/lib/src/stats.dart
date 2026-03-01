class FrequencyStats {
  final int count;
  final int min, max, median, p95, avg;
  final double medianHz, p95Hz, avgHz;

  const FrequencyStats({
    required this.count,
    required this.min,
    required this.max,
    required this.median,
    required this.p95,
    required this.avg,
    required this.medianHz,
    required this.p95Hz,
    required this.avgHz,
  });

  const FrequencyStats.zero()
    : count = 0,
      min = 0,
      max = 0,
      median = 0,
      p95 = 0,
      avg = 0,
      medianHz = 0.0,
      p95Hz = 0.0,
      avgHz = 0.0;

  @override
  String toString() =>
      '''
=== Frequency Analysis ($count events) ===
Interval (µs): min = $min, median = $median, p95 = $p95, max = $max
Average interval: $avg µs
Estimated frequency: median = ${medianHz.toStringAsFixed(2)} Hz, 
                     p95 = ${p95Hz.toStringAsFixed(2)} Hz, 
                     avg = ${avgHz.toStringAsFixed(2)} Hz
''';
}
