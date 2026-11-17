import 'dart:async';

import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Brain extends Mock implements Brain {}

void main() {
  test(
    'intent version changes when queued, even if the FSM ignores it',
    () async {
      final machine = M(_Brain());
      final start = machine.commandVersion;
      machine.add(const A.sitDown()); // Zero ignores this event.
      expect(machine.commandVersion, start + 1);
      expect(machine.state, isA<Zero>());
      await Future<void>.delayed(Duration.zero);
      expect(machine.commandVersion, start + 1);
      expect(machine.state, isA<Zero>());
      final closing = machine.close();
      expect(machine.commandVersion, start + 2);
      await closing;
    },
  );
}
