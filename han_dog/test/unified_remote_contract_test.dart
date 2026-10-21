import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:han_dog/src/real_controller.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

YunZhuoState state({bool h = true, bool button = false, double vx = 0}) =>
    YunZhuoState(
      L1: button,
      L2: button,
      R1: button,
      R2: false,
      leftStick: Vector2(0, vx),
      rightStick: Vector2.zero(),
      H: h,
      G_S: GSState.middle,
      red: false,
      LT: false,
      RT: false,
      knob: 0,
      rawChannels: List.filled(16, SbusValues.center),
    );

void main() {
  test('H must see low; radio loss never replays a held high', () {
    fakeAsync((async) {
      final input = StreamController<bool>.broadcast(sync: true);
      final values = <bool>[];
      final sub = safeEnableRequests(input.stream).listen(values.add);
      input.add(true);
      async.flushMicrotasks();
      expect(values, [false]);
      input.add(false);
      input.add(true);
      async.flushMicrotasks();
      expect(values, [false, true]);
      async.elapse(const Duration(milliseconds: 150));
      expect(values.last, false);
      input.add(true);
      async.flushMicrotasks();
      expect(values.last, false);
      input.add(false);
      input.add(true);
      async.flushMicrotasks();
      expect(values, [false, true, false, true]);
      sub.cancel();
      input.close();
    });
  });

  final buttons = <String, bool Function(YunZhuoState)>{
    'L1': (s) => s.L1,
    'L2': (s) => s.L2,
    'R1': (s) => s.R1,
  };
  for (final entry in buttons.entries) {
    for (final initial in [false, true]) {
      test(
        '${entry.key}: enabled baseline $initial, then either edge once',
        () {
          final input = StreamController<YunZhuoState>.broadcast(sync: true);
          final values = <bool>[];
          var allowed = false;
          var generation = 0;
          var now = DateTime.utc(2026);
          final sub = enabledButtonChanges(
            input.stream,
            entry.value,
            allowed: () => allowed,
            generation: () => generation,
            clock: () => now,
          ).listen(values.add);
          input.add(state(h: false, button: !initial));
          input.add(state(button: initial));
          input.add(state(button: !initial));
          expect(values, isEmpty, reason: 'discard pending-enable flips');
          allowed = true;
          generation++;
          input.add(state(button: initial));
          input.add(state(button: initial));
          expect(
            values,
            isEmpty,
            reason: 'confirmation only establishes baseline',
          );
          input.add(state(button: !initial));
          input.add(state(button: !initial));
          input.add(state(button: initial));
          expect(values, [true, true]);
          generation++;
          input.add(state(button: !initial));
          expect(values, hasLength(2), reason: 'discard old enable baseline');
          now = now.add(const Duration(milliseconds: 150));
          input.add(state(button: initial));
          expect(
            values,
            hasLength(2),
            reason: 'recovered first frame is baseline',
          );
          input.add(state(button: !initial));
          expect(values, hasLength(3));
          allowed = false;
          input.add(state(button: initial));
          allowed = true;
          input.add(state(button: !initial));
          expect(values, hasLength(3));
          input.add(state(button: initial));
          expect(values, hasLength(4));
          sub.cancel();
          input.close();
        },
      );
    }
  }

  test(
    'red disables on startup pressed or new press, never on release',
    () async {
      final input = StreamController<bool>(sync: true);
      final values = <bool>[];
      final sub = redButtonPressEvents(input.stream).listen(values.add);
      input.add(true);
      input.add(true);
      input.add(false);
      input.add(false);
      input.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(values, [true, true]);
      await input.close();
      await sub.cancel();
    },
  );

  test('velocity needs confirmed enable and a new neutral frame each time', () {
    final input = StreamController<YunZhuoState>.broadcast(sync: true);
    final values = <Vector3>[];
    var allowed = false;
    var generation = 0;
    final sub = enabledDirection(
      input.stream,
      'standard',
      allowed: () => allowed,
      generation: () => generation,
    ).listen(values.add);
    input.add(state(h: false, vx: 1));
    input.add(state(vx: 1));
    allowed = true;
    generation++;
    input.add(state(vx: 1));
    expect(values.every((v) => v.length == 0), isTrue);
    input.add(state());
    input.add(state(vx: .6));
    expect(values.last.x, closeTo(.6, 1e-6));
    generation++;
    input.add(state(vx: 1));
    expect(values.last.length, 0);
    input.add(state());
    input.add(state(vx: -.4));
    expect(values.last.x, closeTo(-.4, 1e-6));
    sub.cancel();
    input.close();
  });
}
