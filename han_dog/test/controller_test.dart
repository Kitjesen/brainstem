import 'dart:async';
import 'package:han_dog/src/real_controller.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';


void main() {
  group('L1 enable order', () {
    late StreamController<YunZhuoState> input;
    late StreamSubscription<bool> subscription;
    late List<bool> actions;
    late bool allowed;
    late int generation;
    late DateTime now;

    void frame({bool h = true, bool l1 = false}) {
      input.add(YunZhuoState(
        L1: l1,
        L2: false,
        R1: false,
        R2: false,
        leftStick: Vector2.zero(),
        rightStick: Vector2.zero(),
        H: h,
        G_S: GSState.middle,
        red: false,
        LT: false,
        RT: false,
        knob: 0,
        rawChannels: List<int>.filled(16, SbusValues.center),
      ));
    }

    setUp(() {
      input = StreamController<YunZhuoState>.broadcast(sync: true);
      actions = [];
      allowed = false;
      generation = 0;
      now = DateTime.utc(2026);
      subscription = enabledStandUpPresses(
        input.stream,
        allowed: () => allowed,
        generation: () => generation,
        clock: () => now,
      ).listen(actions.add);
    });

    tearDown(() async {
      await subscription.cancel();
      await input.close();
    });

    test('disabled L1 changes are discarded, not replayed by H', () {
      frame(h: false);
      frame(h: false, l1: true);
      frame(l1: true);
      allowed = true;
      generation++;
      frame(l1: true);
      frame(l1: true);
      expect(actions, isEmpty);
      frame();
      expect(actions, [true]);
    });

    for (final initial in [false, true]) {
      test('first new flip from $initial works after waiting two seconds', () {
        frame(h: false, l1: initial);
        frame(l1: initial);
        allowed = true;
        generation++;
        for (var i = 0; i < 200; i++) {
          now = now.add(const Duration(milliseconds: 10));
          frame(l1: initial);
        }
        expect(actions, isEmpty);
        frame(l1: !initial);
        frame(l1: !initial);
        expect(actions, [true]);
        frame(l1: initial);
        frame(l1: initial);
        expect(actions, [true, true]);
      });

      test('startup baseline $initial never requests standing', () {
        allowed = true;
        frame(l1: initial);
        frame(l1: initial);
        expect(actions, isEmpty);
      });
    }

    test('every new flip emits once, repeated identical frames do not', () {
      allowed = true;
      frame();
      frame(l1: true);
      frame(l1: true);
      frame();
      frame();
      expect(actions, [true, true]);
      frame(l1: true);
      expect(actions, [true, true, true]);
    });

    test('startup held L1 and simultaneous H/L1 cannot request standing', () {
      allowed = true;
      frame(l1: true);
      expect(actions, isEmpty);
      frame(h: false);
      frame(l1: true);
      expect(actions, isEmpty);
      frame();
      expect(actions, [true]);
    });

    test('all pending-enable flips are discarded; completion only baselines', () {
      frame();
      frame(l1: true);
      frame();
      frame(l1: true);
      expect(actions, isEmpty);
      allowed = true;
      generation++;
      frame();
      frame();
      expect(actions, isEmpty);
      frame(l1: true);
      expect(actions, [true]);
    });

    test('new enable generation discards the old baseline', () {
      allowed = true;
      frame();
      generation += 2;
      frame(l1: true);
      expect(actions, isEmpty);
      frame();
      expect(actions, [true]);
    });

    test('disabled frames discard the baseline even without a generation change', () {
      allowed = true;
      frame();
      frame(h: false, l1: true);
      frame(h: false);
      frame(l1: true);
      expect(actions, isEmpty);
      frame();
      expect(actions, [true]);
    });

    test('revoked enable discards the baseline until a fresh enabled frame', () {
      allowed = true;
      frame();
      allowed = false;
      frame(l1: true);
      allowed = true;
      frame();
      expect(actions, isEmpty);
      frame(l1: true);
      expect(actions, [true]);
    });

    for (final gapMs in [150, 151, 2000]) {
      test('input gap $gapMs ms uses the first recovered frame only as baseline', () {
        allowed = true;
        frame();
        now = now.add(Duration(milliseconds: gapMs));
        frame(l1: true);
        frame(l1: true);
        expect(actions, isEmpty);
        frame();
        expect(actions, [true]);
      });
    }

    test('a sub-timeout input interval preserves the baseline', () {
      allowed = true;
      frame();
      now = now.add(const Duration(milliseconds: 149));
      frame(l1: true);
      expect(actions, [true]);
    });
  });

  test(
    'timeout then decay; new cmd cancels decay and outputs immediately',
    () async {
      final controlController = StreamController<double>();
      final output$ = watchdogDecay(
        controlController.stream,
        timeout: Duration(milliseconds: 50),
        steps: 10,
        stepPeriod: Duration(milliseconds: 50),
        decayCurve: (s0, t) => s0 * t,
      );
      final outputs = <double>[];
      output$.listen(outputs.add);
      controlController.add(1); // t=0
      await Future<void>.delayed(Duration(milliseconds: 20));
      controlController.add(2); // t=20
      await Future<void>.delayed(Duration(milliseconds: 20));
      controlController.add(3); // t=40
      await Future<void>.delayed(Duration(milliseconds: 60));
      // t=160: timeout -> decay from (3,3,3)
      await Future<void>.delayed(Duration(milliseconds: 120));
      controlController.add(4); // t=460
      await Future<void>.delayed(Duration(milliseconds: 300));
      // t=210: decay step 1
      print(outputs);
    },
  );
}
