import 'package:fake_async/fake_async.dart';
import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockM extends Mock implements M {}

void main() {
  late MockM mockM;

  setUpAll(() {
    registerFallbackValue(const A.init());
  });

  setUp(() {
    mockM = MockM();
    when(() => mockM.state).thenReturn(const Zero());
    when(() => mockM.stream).thenAnswer((_) => const Stream.empty());
  });

  group('initial state', () {
    test('owner is null', () {
      final arbiter = ControlArbiter(mockM);
      expect(arbiter.owner, isNull);
    });

    test('state delegates to M', () {
      when(() => mockM.state).thenReturn(const Zero());
      final arbiter = ControlArbiter(mockM);
      expect(arbiter.state, isA<Zero>());
    });
  });

  group('command acquisition', () {
    test('yunzhuo acquires when no owner → true, M.add called', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        final result = arbiter.command(const A.standUp(), ControlSource.yunzhuo);

        expect(result, isTrue);
        expect(arbiter.owner, ControlSource.yunzhuo);
        verify(() => mockM.add(const A.standUp())).called(1);
      });
    });

    test('grpc acquires when no owner → true', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        final result = arbiter.command(const A.standUp(), ControlSource.grpc);

        expect(result, isTrue);
        expect(arbiter.owner, ControlSource.grpc);
        verify(() => mockM.add(any())).called(1);
      });
    });

    test('same source continues → true', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        arbiter.command(const A.standUp(), ControlSource.yunzhuo);
        final result = arbiter.command(const A.sitDown(), ControlSource.yunzhuo);

        expect(result, isTrue);
        expect(arbiter.owner, ControlSource.yunzhuo);
        verify(() => mockM.add(any())).called(2);
      });
    });
  });

  group('preemption', () {
    test('yunzhuo preempts grpc → true, ownerStream emits', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);
        final ownerEvents = <ControlSource?>[];
        arbiter.ownerStream.listen(ownerEvents.add);

        arbiter.command(const A.standUp(), ControlSource.grpc);
        arbiter.command(const A.sitDown(), ControlSource.yunzhuo);
        async.flushMicrotasks(); // broadcast stream delivers asynchronously

        expect(arbiter.owner, ControlSource.yunzhuo);
        // ownerStream: grpc acquired, then yunzhuo preempted
        expect(ownerEvents, [ControlSource.grpc, ControlSource.yunzhuo]);
      });
    });

    test('grpc cannot preempt yunzhuo → false, M.add NOT called', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        arbiter.command(const A.standUp(), ControlSource.yunzhuo);
        reset(mockM);
        when(() => mockM.state).thenReturn(const Zero());

        final result = arbiter.command(const A.sitDown(), ControlSource.grpc);

        expect(result, isFalse);
        expect(arbiter.owner, ControlSource.yunzhuo);
        verifyNever(() => mockM.add(any()));
      });
    });
  });

  group('timeout', () {
    test('auto-release after 3 seconds → owner null', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);
        final ownerEvents = <ControlSource?>[];
        arbiter.ownerStream.listen(ownerEvents.add);

        arbiter.command(const A.standUp(), ControlSource.grpc);
        expect(arbiter.owner, ControlSource.grpc);

        async.elapse(const Duration(seconds: 3));
        expect(arbiter.owner, isNull);
        expect(ownerEvents, [ControlSource.grpc, null]);
      });
    });

    test('new command resets timer', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        arbiter.command(const A.standUp(), ControlSource.grpc);
        async.elapse(const Duration(seconds: 2));
        expect(arbiter.owner, ControlSource.grpc);

        // Reset timer by sending another command
        arbiter.command(const A.sitDown(), ControlSource.grpc);
        async.elapse(const Duration(seconds: 2));
        expect(arbiter.owner, ControlSource.grpc); // not released yet

        async.elapse(const Duration(seconds: 1));
        expect(arbiter.owner, isNull); // released after 3s from last command
      });
    });

    test('custom timeout duration', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(
          mockM,
          timeout: const Duration(seconds: 1),
        );

        arbiter.command(const A.standUp(), ControlSource.grpc);
        async.elapse(const Duration(milliseconds: 999));
        expect(arbiter.owner, ControlSource.grpc);

        async.elapse(const Duration(milliseconds: 1));
        expect(arbiter.owner, isNull);
      });
    });
  });

  group('manual release', () {
    test('release matching source → owner null', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        arbiter.command(const A.standUp(), ControlSource.grpc);
        arbiter.release(ControlSource.grpc);

        expect(arbiter.owner, isNull);
      });
    });

    test('release non-matching source → no change', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        arbiter.command(const A.standUp(), ControlSource.yunzhuo);
        arbiter.release(ControlSource.grpc);

        expect(arbiter.owner, ControlSource.yunzhuo);
      });
    });
  });

  group('safety bypass', () {
    test('fault always passes regardless of owner', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        // Give ownership to yunzhuo
        arbiter.command(const A.standUp(), ControlSource.yunzhuo);
        reset(mockM);

        arbiter.fault('test error');
        verify(() => mockM.add(any(that: isA<Fault>()))).called(1);
      });
    });

    test('init always passes regardless of owner', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);

        arbiter.command(const A.standUp(), ControlSource.yunzhuo);
        reset(mockM);

        arbiter.init();
        verify(() => mockM.add(any(that: isA<Init>()))).called(1);
      });
    });
  });

  group('ownerStream', () {
    test('emits acquire, preempt, release, timeout in order', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);
        final events = <ControlSource?>[];
        arbiter.ownerStream.listen(events.add);

        // 1. grpc acquires
        arbiter.command(const A.standUp(), ControlSource.grpc);
        // 2. yunzhuo preempts
        arbiter.command(const A.sitDown(), ControlSource.yunzhuo);
        // 3. yunzhuo manual release
        arbiter.release(ControlSource.yunzhuo);
        // 4. grpc acquires, then timeout
        arbiter.command(const A.standUp(), ControlSource.grpc);
        async.elapse(const Duration(seconds: 3));

        expect(events, [
          ControlSource.grpc,   // 1. acquired
          ControlSource.yunzhuo, // 2. preempted
          null,                  // 3. released
          ControlSource.grpc,   // 4. acquired
          null,                  // 5. timeout
        ]);
      });
    });
  });

  group('dispose', () {
    test('cancels timer and closes stream', () {
      fakeAsync((async) {
        final arbiter = ControlArbiter(mockM);
        arbiter.command(const A.standUp(), ControlSource.grpc);
        arbiter.dispose();

        // Should not throw when timer would have fired
        async.elapse(const Duration(seconds: 5));
      });
    });
  });
}
