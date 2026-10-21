import 'dart:async';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_brain/src/behaviour.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockBrain extends Mock implements Brain {}

class MockIdle extends Mock implements Idle {}

class MockStandUp extends Mock implements StandUp {}

class MockSitDown extends Mock implements SitDown {}

class MockMemory extends Mock implements Memory<History> {}

class Frame extends Fake implements History {}

void main() {
  test(
    'fault burst and re-entry retain exactly one control subscription',
    () async {
      final ticks = StreamController<History>.broadcast();
      Stream<History> transition() async* {
        await for (final h in ticks.stream) {
          yield h;
        }
      }

      final brain = MockBrain();
      final idle = MockIdle();
      final stand = MockStandUp();
      final sit = MockSitDown();
      final memory = MockMemory();
      when(() => brain.idle).thenReturn(idle);
      when(() => brain.standUp).thenReturn(stand);
      when(() => brain.sitDown).thenReturn(sit);
      when(() => brain.memory).thenReturn(memory);
      when(() => idle.doing).thenAnswer((_) => ticks.stream);
      when(() => stand.doing).thenAnswer((_) => transition());
      when(() => sit.doing).thenAnswer((_) => transition());
      final m = M(brain);
      final history = Frame();
      var inputTicks = 0;
      var outputTicks = 0;
      when(() => memory.add(history)).thenAnswer((_) {
        outputTicks++;
      });
      final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        inputTicks++;
        ticks.add(history);
      });
      try {
        m.add(const A.init());
        await m.stream
            .firstWhere((s) => s is Grounded)
            .timeout(const Duration(seconds: 1));
        for (var cycle = 0; cycle < 3; cycle++) {
          m.add(const A.standUp());
          await m.stream
              .firstWhere((s) => s is Transitioning)
              .timeout(const Duration(seconds: 1));
          await Future<void>.delayed(Duration.zero);
          for (var i = 0; i < 32; i++) {
            m.add(A.fault('motor fault $i'));
          }
          // Let async* cancellation finish just as a real clock tick would.
          ticks.add(history);
          await m.stream
              .firstWhere((s) => s is Grounded)
              .timeout(const Duration(seconds: 1));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final beforeIn = inputTicks;
          final beforeOut = outputTicks;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(outputTicks - beforeOut, inputTicks - beforeIn);
        }
        await m.close();
        clearInteractions(memory);
        ticks.add(history);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        verifyNever(() => memory.add(history));
      } finally {
        if (!m.isClosed) await m.close();
        timer.cancel();
        await ticks.close();
      }
    },
  );
}
