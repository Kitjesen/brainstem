import 'dart:async';

import 'package:han_dog/src/real_controller.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockPort extends Mock
    implements SerialPortController<Never, YunZhuoState> {}

YunZhuoState frame() => YunZhuoState(
  L1: false,
  L2: false,
  R1: false,
  R2: false,
  leftStick: Vector2.zero(),
  rightStick: Vector2.zero(),
  H: false,
  G_S: GSState.middle,
  red: false,
  LT: false,
  RT: false,
  knob: 0,
  rawChannels: List<int>.filled(16, SbusValues.center),
);

void main() {
  test(
    '150ms stop persists through synthetic zero; only fresh frames clear it',
    () async {
      var now = DateTime.utc(2026);
      final controller = RealController(
        '/dev/test-only-no-hardware',
        () => now,
      );
      final port = MockPort();
      final frames = StreamController<Iterable<YunZhuoState>>.broadcast(
        sync: true,
      );
      when(() => port.open()).thenReturn(true);
      when(() => port.state).thenAnswer((_) => frames.stream);
      controller.port.dispose();
      controller.port = port;
      expect(controller.open(), isTrue); // Mock port: no serial I/O.
      expect(controller.hardStopActive, isTrue);
      var stops = 0;
      var nextDirection = Completer<bool>();
      final hardSub = controller.hardStop.listen((_) => stops++);
      final dirSub = controller.direction.listen((_) {
        if (!nextDirection.isCompleted) {
          nextDirection.complete(controller.hardStopActive);
        }
      }, onError: (Object _) {});
      Future<bool> received() =>
          nextDirection.future.timeout(const Duration(seconds: 3));
      try {
        frames.add([frame()]);
        expect(await received(), isFalse);
        now = now.add(const Duration(milliseconds: 149));
        expect(controller.hardStopActive, isFalse);
        nextDirection = Completer<bool>();
        now = now.add(const Duration(milliseconds: 3));
        expect(await received(), isTrue);
        expect(stops, 1);
        expect(
          controller.inputHealthy,
          isTrue,
        ); // 500ms health is NOT the stop gate.
        frames.add([]);
        await Future<void>.delayed(Duration.zero);
        expect(controller.hardStopActive, isTrue);
        nextDirection = Completer<bool>();
        frames.add([frame()]);
        expect(await received(), isFalse);
        expect(controller.hardStopActive, isFalse);
        frames.addError(StateError('mock disconnect'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.hardStopActive, isTrue);
      } finally {
        await hardSub.cancel();
        await dirSub.cancel();
        controller.dispose();
        await frames.close();
      }
    },
  );
}
