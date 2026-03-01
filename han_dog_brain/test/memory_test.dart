import 'package:han_dog_brain/src/memory.dart';
import 'package:test/test.dart';

void main() {
  test('init', () {
    final size = 3;
    final initial = 1;
    final m = Memory(historySize: size, initial: initial);
    expect(m.histories, List.filled(size, initial));
  });

  test('add and histories', () {
    final size = 3;
    final initial = 0;
    final m = Memory(historySize: size, initial: initial);
    m.add(1);
    expect(m.histories, [0, 0, 1]);
    m.add(2);
    expect(m.histories, [0, 1, 2]);
    m.add(3);
    expect(m.histories, [1, 2, 3]);
  });

  test('latest and next', () {
    final size = 3;
    final initial = 0;
    final m = Memory(historySize: size, initial: initial);
    expect(m.latest, 0);
    expectLater(m.next, completion(equals(1)));
    m.add(1);
    expect(m.latest, 1);
    expectLater(m.next, completion(equals(2)));
    m.add(2);
    expect(m.latest, 2);
    expectLater(m.next, completion(equals(3)));
    m.add(3);
    expect(m.latest, 3);
  });

  group("next stream", () {
    test('case 1', () {
      final size = 3;
      final initial = 0;
      final m = Memory(historySize: size, initial: initial);
      expectLater(m.nextStream, emitsInOrder([1, 2, 3]));
      m.add(1);
      expectLater(m.nextStream, emitsInOrder([2, 3]));
      m.add(2);
      expectLater(m.nextStream, emitsInOrder([3]));
      m.add(3);
      expectLater(m.nextStream, emitsInOrder([]));
    });

    test('case n', () {
      final size = 3;
      final initial = 0;
      final m = Memory(historySize: size, initial: initial);
      final n = 30;
      final s = List.generate(n, (i) => i);
      while (s.isNotEmpty) {
        expectLater(m.nextStream, emitsInOrder(s));
        final v = s.removeAt(0);
        m.add(v);
      }
    });
  });
}
