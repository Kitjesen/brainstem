import 'dart:convert';
import 'dart:io';

import 'package:thunder/src/web_zero_stability.dart';
import 'package:test/test.dart';

void main() {
  late DateTime clock;
  late ZeroStabilityWindow window;
  setUp(() {
    clock = DateTime.utc(2026);
    window = ZeroStabilityWindow(clock: () => clock);
  });

  void frame(int index, {int? moving, bool velocityOnly = false}) {
    clock = DateTime.utc(2026).add(Duration(milliseconds: index * 10));
    const noise = [-.30, .20, .10, -.20, .30, -.10];
    for (var id = 0; id < 16; id++) {
      window.record(
        id,
        position: id == moving && !velocityOnly
            ? index * .0002
            : (index.isEven ? .0004 : -.0004),
        velocity: id == moving ? .2 : noise[index % noise.length],
      );
    }
  }

  test('zero-centred RS02 velocity noise passes only after a full window', () {
    for (var i = 0; i < 50; i++) {
      frame(i);
    }
    expect(window.blockReason(), isNotNull);
    frame(50);
    expect(window.blockReason(), isNull);
    for (var i = 51; i < 200; i++) {
      frame(i);
      expect(window.blockReason(), isNull);
    }
  });

  test('position drift is rejected even with cancelling velocity samples', () {
    for (var i = 0; i <= 50; i++) {
      frame(i);
      window.record(7, position: i * .0002, velocity: 0);
    }
    expect(window.blockReason(), contains('FL Foot'));
  });

  test('persistent reported velocity is rejected despite a frozen angle', () {
    for (var i = 0; i <= 50; i++) {
      frame(i, moving: 2, velocityOnly: true);
    }
    expect(window.blockReason(), contains('FR Calf'));
  });

  test(
    'actual motion and its return remain blocked until they leave window',
    () {
      for (var i = 0; i <= 50; i++) {
        frame(i);
      }
      clock = clock.add(const Duration(milliseconds: 1));
      window.record(4, position: .02, velocity: 0);
      expect(window.blockReason(), contains('FL Hip'));
      for (var i = 51; i <= 100; i++) {
        frame(i);
      }
      expect(window.blockReason(), contains('FL Hip'));
      frame(102);
      expect(window.blockReason(), isNull);
    },
  );

  test('one absent motor never becomes ready', () {
    for (var i = 0; i <= 50; i++) {
      clock = DateTime.utc(2026).add(Duration(milliseconds: i * 10));
      for (var id = 0; id < 15; id++) {
        window.record(id, position: 0, velocity: 0);
      }
    }
    expect(window.blockReason(), contains('RL Foot'));
  });

  test('stale samples and report gaps require a fresh continuous window', () {
    for (var i = 0; i <= 50; i++) {
      frame(i);
    }
    clock = clock.add(const Duration(milliseconds: 120));
    expect(window.blockReason(), isNotNull);
    frame(63);
    expect(window.blockReason(), isNotNull);
    for (var i = 64; i <= 113; i++) {
      frame(i);
    }
    expect(window.blockReason(), isNull);
  });

  test('fault, invalid data and clock rollback discard evidence', () {
    for (var i = 0; i <= 50; i++) {
      frame(i);
    }
    window.record(3, position: 0, velocity: 0, healthy: false);
    expect(window.blockReason(), contains('FR Foot'));
    for (var i = 51; i <= 101; i++) {
      frame(i);
    }
    expect(window.blockReason(), isNull);
    window.record(0, position: double.nan, velocity: 0);
    expect(window.blockReason(), contains('FR Hip'));
    for (var i = 102; i <= 152; i++) {
      frame(i);
    }
    expect(window.blockReason(), isNull);
    clock = DateTime.utc(2025);
    expect(window.blockReason(), isNotNull);
  });

  test(
    'one cached reading cannot mature; clear also invalidates readiness',
    () {
      for (var id = 0; id < 16; id++) {
        window.record(id, position: 0, velocity: 0);
      }
      clock = clock.add(const Duration(milliseconds: 500));
      expect(window.blockReason(), isNotNull);
      for (var i = 51; i <= 101; i++) {
        frame(i);
      }
      expect(window.blockReason(), isNull);
      window.clear();
      expect(window.blockReason(), isNotNull);
    },
  );

  final trace = Platform.environment['ZERO_STABILITY_TRACE'];
  test(
    'recorded passive static feedback remains continuously ready',
    () {
      final data = jsonDecode(File(trace!).readAsStringSync()) as Map;
      expect(data['read_only'], true);
      expect(data['can_send_calls'], 0);
      var readyFrames = 0;
      for (final raw in data['samples'] as List) {
        final row = raw as List;
        clock = DateTime.utc(2026).add(Duration(microseconds: row[0] as int));
        window.record(
          row[1] as int,
          position: (row[2] as num).toDouble(),
          velocity: (row[3] as num).toDouble(),
          healthy: row[4] == 0 && row[5] == 0,
        );
        if ((row[0] as int) > 700000) {
          expect(window.blockReason(), isNull);
          readyFrames++;
        }
      }
      expect(readyFrames, greaterThan(1000));
    },
    skip: trace == null
        ? 'Set ZERO_STABILITY_TRACE for recorded hardware replay'
        : false,
  );
}
