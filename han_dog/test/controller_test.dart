import 'dart:async';
import 'package:han_dog/src/real_controller.dart';
import 'package:test/test.dart';


void main() {
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
