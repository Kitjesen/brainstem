import 'dart:async';
import 'dart:collection';

import 'package:pcan/pcan.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

class FakePcan extends Pcan {
  FakePcan() : super(PcanChannel.usbbus1);
  final results = Queue<PcanStatus>();
  final writes = <PcanMessage>[];
  @override
  PcanStatus write(PcanMessage message) {
    writes.add(message);
    return results.isEmpty ? PcanStatus.ok : results.removeFirst();
  }

  @override
  PcanStatus close() => PcanStatus.ok;
}

void main() {
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
