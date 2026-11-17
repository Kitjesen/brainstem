import 'dart:async';
import 'dart:collection';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

class FakePcan extends Pcan {
  FakePcan() : super(PcanChannel.usbbus1);
  final results = Queue<PcanStatus>();
  final writes = <PcanMessage>[];
  final writeTimes = <int>[];
  final watch = Stopwatch()..start();
  @override
  PcanStatus write(PcanMessage message) {
    writes.add(message);
    writeTimes.add(watch.elapsedMicroseconds);
    return results.isEmpty ? PcanStatus.ok : results.removeFirst();
  }

  @override
  PcanStatus close() => PcanStatus.ok;
}

class ManualStopwatch implements Stopwatch {
  int micros = 0;
  @override
  int get elapsedMicroseconds => micros;
  @override
  int get elapsedMilliseconds => micros ~/ 1000;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'confirmed immediate calibration never queues or retries a failed send',
    () async {
      final can = FakePcan()..results.add(PcanStatus.xmtfull);
      final c = PcanController<RSEvent, RSState>.withPcan(can);
      expect(c.tryWriteImmediately(RSEvent.setZero(1)), false);
      expect(c.pendingWrites, 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(can.writes, hasLength(1));
      expect(c.tryWriteImmediately(RSEvent.setZero(2)), true);
      expect(can.writes, hasLength(2));
      c.dispose();
      expect(c.tryWriteImmediately(RSEvent.setZero(3)), false);
      expect(can.writes, hasLength(2));
    },
  );

  test(
    'calibration refuses paced or already queued transport before writing',
    () {
      final can = FakePcan();
      final paced = PcanController<RSEvent, RSState>.withPcan(
        can,
        writeInterval: const Duration(milliseconds: 5),
      );
      expect(paced.tryWriteImmediately(RSEvent.setZero(1)), false);
      expect(can.writes, isEmpty);
      paced.dispose();
      final busyCan = FakePcan()..results.add(PcanStatus.xmtfull);
      final busy = PcanController<RSEvent, RSState>.withPcan(busyCan);
      busy.add(RSEvent.getDeviceId(1));
      expect(busy.pendingWrites, 1);
      expect(busy.tryWriteImmediately(RSEvent.setZero(1)), false);
      expect(busyCan.writes, hasLength(1));
      busy.dispose();
    },
  );

  test('paced controls coalesce without delaying another PCAN leg', () async {
    final at = FakePcan();
    // First-use ARM JIT work must not advance this queue-ordering test's clock.
    final clock = ManualStopwatch();
    final paced = PcanController<RSEvent, RSState>.withPcan(
      at,
      writeInterval: const Duration(milliseconds: 5),
      clock: clock,
    );
    final pcan = FakePcan();
    final immediate = PcanController<RSEvent, RSState>.withPcan(pcan);
    paced.add(RSEvent.setReporting(1));
    paced.add(RSEvent.control(1, position: 0.1));
    final latest = RSEvent.control(1, position: 0.2);
    paced.add(latest);
    for (var id = 1; id <= 4; id++) {
      immediate.add(RSEvent.control(id));
    }
    expect(pcan.writes, hasLength(4));
    expect(paced.pendingWrites, 1);
    clock.micros = 5000;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(at.writes, hasLength(2));
    expect(at.writes.last.data, latest.toCanFrame().data);
    paced.dispose();
    immediate.dispose();
  });
  test(
    'AT pacing queues a burst without treating it as failed CAN writes',
    () async {
      final can = FakePcan();
      final c = PcanController<RSEvent, RSState>.withPcan(
        can,
        writeInterval: const Duration(milliseconds: 5),
      );
      for (var id = 1; id <= 4; id++) {
        c.add(RSEvent.setReporting(id));
      }
      expect(can.writes, hasLength(1));
      expect(c.pendingWrites, 3);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(can.writes, hasLength(4));
      expect(c.failedWrites, 0);
      expect(c.pendingWrites, 0);
      for (var i = 1; i < can.writeTimes.length; i++) {
        expect(
          can.writeTimes[i] - can.writeTimes[i - 1],
          greaterThanOrEqualTo(5000),
        );
      }
      c.dispose();
    },
  );
  test(
    'paced stop preempts queued motion and enable without blocking PCAN',
    () async {
      final can = FakePcan();
      final c = PcanController<RSEvent, RSState>.withPcan(
        can,
        writeInterval: const Duration(milliseconds: 5),
      );
      c.add(RSEvent.setReporting(1));
      c.add(RSEvent.control(1, position: 0.1));
      c.add(RSEvent.enable(1));
      c.add(RSEvent.setReporting(2));
      final stop = RSEvent.disable(1);
      c.add(stop);
      c.add(RSEvent.control(1, position: 0.2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(can.writes, hasLength(3));
      expect(can.writes[1].id, stop.toCanFrame().id);
      expect(c.pendingWrites, 0);
      c.dispose();
    },
  );
  test('close clears paced writes instead of sending them later', () async {
    final can = FakePcan();
    final c = PcanController<RSEvent, RSState>.withPcan(
      can,
      writeInterval: const Duration(milliseconds: 5),
    );
    c.add(RSEvent.setReporting(1));
    c.add(RSEvent.setReporting(2));
    c.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(can.writes, hasLength(1));
    expect(c.pendingWrites, 0);
    c.dispose();
  });
  test(
    'both full statuses retry asynchronously and stop after three attempts',
    () async {
      for (final status in [PcanStatus.xmtfull, PcanStatus.qxmtfull]) {
        final can = FakePcan()..results.addAll(List.filled(6, status));
        final c = PcanController<RSEvent, RSState>.withPcan(can);
        c.add(RSEvent.setReporting(1));
        expect(can.writes, hasLength(1));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(can.writes, hasLength(3));
        expect(c.pendingWrites, 0);
        c.dispose();
      }
    },
  );
  test('newest motion replaces a failed older target', () async {
    final can = FakePcan()
      ..results.addAll([PcanStatus.xmtfull, PcanStatus.xmtfull]);
    final c = PcanController<RSEvent, RSState>.withPcan(can);
    c.add(RSEvent.control(1, position: 0.1));
    final latest = RSEvent.control(1, position: 0.2);
    c.add(latest);
    expect(c.pendingWrites, 1);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(can.writes, hasLength(3));
    expect(can.writes.last.data, latest.toCanFrame().data);
    c.dispose();
  });
  test(
    'stop cancels stale motion and queued enable; later motion stays blocked',
    () async {
      final can = FakePcan()
        ..results.addAll(List.filled(3, PcanStatus.xmtfull));
      final c = PcanController<RSEvent, RSState>.withPcan(can);
      c.add(RSEvent.control(1, position: 0.1));
      c.add(RSEvent.enable(1));
      final stop = RSEvent.disable(1);
      c.add(stop);
      c.add(RSEvent.control(1, position: 0.2));
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(can.writes, hasLength(4));
      expect(can.writes.last.id, stop.toCanFrame().id);
      expect(c.pendingWrites, 0);
      c.dispose();
    },
  );
  test('non-retryable failure and close do not leave delayed writes', () async {
    final can = FakePcan()
      ..results.addAll([PcanStatus.busoff, PcanStatus.xmtfull]);
    final c = PcanController<RSEvent, RSState>.withPcan(can);
    c.add(RSEvent.control(1));
    expect(c.pendingWrites, 0);
    c.add(RSEvent.control(2));
    c.close();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(can.writes, hasLength(2));
    c.dispose();
  });
}
