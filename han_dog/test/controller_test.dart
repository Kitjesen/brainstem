import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:han_dog/src/real_controller.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

void main() {
  test('new command cancels active decay and outputs immediately', () {
    fakeAsync((async) {
      final input = StreamController<double>.broadcast(sync: true);
      final output = <double>[];
      watchdogDecay(
        input.stream,
        timeout: const Duration(milliseconds: 50),
        steps: 2,
        stepPeriod: const Duration(milliseconds: 50),
        decayCurve: (s0, t) => s0 * t,
      ).listen(output.add);

      input.add(1.0);
      async.flushMicrotasks();
      expect(output.last, 1.0);

      async.elapse(const Duration(milliseconds: 100));
      expect(output.last, 0.5);

      input.add(2.0);
      async.flushMicrotasks();
      expect(output.last, 2.0);

      async.elapse(const Duration(milliseconds: 50));
      expect(output.last, 2.0);
    });
  });

  test('YUNZHUO right-stick up is a positive body-height axis', () {
    final channels = List<int>.filled(16, SbusValues.center);
    channels[1] = SbusValues.low;
    channels[4] = SbusValues.center;

    final state = YunZhuoState.fromChannels(channels, 0);

    expect(state.rightStick.y, closeTo(1.0, 1e-12));
  });

  test('body-height axis fails safe to zero after 150 ms', () {
    fakeAsync((async) {
      final input = StreamController<double>.broadcast(sync: true);
      final output = <double>[];
      bodyHeightAxisWithWatchdog(input.stream).listen(output.add);

      input.add(0.6);
      async.flushMicrotasks();
      expect(output.last, 0.6);

      async.elapse(const Duration(milliseconds: 149));
      expect(output.last, 0.6);

      async.elapse(const Duration(milliseconds: 2));
      expect(output.last, 0.0);
    });
  });

  test('new body-height input restarts the watchdog', () {
    fakeAsync((async) {
      final input = StreamController<double>.broadcast(sync: true);
      final output = <double>[];
      bodyHeightAxisWithWatchdog(input.stream).listen(output.add);

      input.add(0.4);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 100));

      input.add(-0.7);
      async.flushMicrotasks();
      expect(output.last, -0.7);

      async.elapse(const Duration(milliseconds: 149));
      expect(output.last, -0.7);

      async.elapse(const Duration(milliseconds: 2));
      expect(output.last, 0.0);
    });
  });
}
