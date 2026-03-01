import 'package:frequency_watch/frequency_watch.dart';
import 'package:test/test.dart';

void main() {
  group('FrequencyWatch', () {
    late FrequencyWatch fw;

    setUp(() {
      fw = FrequencyWatch(windowSize: 10);
    });

    test('returns zero stats with no events', () {
      final stats = fw.current;
      expect(stats.count, 0);
      expect(stats.min, 0);
      expect(stats.max, 0);
      expect(stats.avg, 0);
      expect(stats.avgHz, 0.0);
    });

    test('returns zero stats with single event (need at least 2 for intervals)', () {
      fw.watch();
      final stats = fw.current;
      // With < 2 timestamps, current returns FrequencyStats.zero()
      expect(stats.count, 0);
      expect(stats.min, 0);
      expect(stats.max, 0);
      expect(stats.avgHz, 0.0);
    });

    test('computes stats with multiple events', () {
      for (int i = 0; i < 5; i++) {
        fw.watch();
        // Busy-wait a tiny bit to ensure non-zero intervals
        final sw = Stopwatch()..start();
        while (sw.elapsedMicroseconds < 100) {}
      }
      final stats = fw.current;
      expect(stats.count, 5);
      expect(stats.min, greaterThan(0));
      expect(stats.max, greaterThanOrEqualTo(stats.min));
      expect(stats.median, greaterThan(0));
      expect(stats.avg, greaterThan(0));
      expect(stats.avgHz, greaterThan(0.0));
      expect(stats.medianHz, greaterThan(0.0));
      expect(stats.p95Hz, greaterThan(0.0));
    });

    test('window size limits stored events', () {
      // windowSize = 10, add 15 events
      for (int i = 0; i < 15; i++) {
        fw.watch();
        final sw = Stopwatch()..start();
        while (sw.elapsedMicroseconds < 50) {}
      }
      final stats = fw.current;
      expect(stats.count, 10);
    });

    test('reset clears all timestamps', () {
      for (int i = 0; i < 5; i++) {
        fw.watch();
      }
      fw.reset();
      final stats = fw.current;
      expect(stats.count, 0);
      expect(stats.avg, 0);
    });

    test('default windowSize is 100', () {
      final defaultFw = FrequencyWatch();
      for (int i = 0; i < 120; i++) {
        defaultFw.watch();
      }
      expect(defaultFw.current.count, 100);
    });

    test('toString returns non-empty string', () {
      for (int i = 0; i < 3; i++) {
        fw.watch();
        final sw = Stopwatch()..start();
        while (sw.elapsedMicroseconds < 100) {}
      }
      final str = fw.toString();
      expect(str, contains('Frequency Analysis'));
      expect(str, contains('Hz'));
    });

    test('p95 is between median and max', () {
      for (int i = 0; i < 10; i++) {
        fw.watch();
        final sw = Stopwatch()..start();
        while (sw.elapsedMicroseconds < 100) {}
      }
      final stats = fw.current;
      expect(stats.p95, greaterThanOrEqualTo(stats.median));
      expect(stats.p95, lessThanOrEqualTo(stats.max));
    });
  });
}
