import 'package:han_dog/src/server/gain_manager.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final _kpInfer = JointsMatrix.fromList(List.filled(16, 10.0));
final _kdInfer = JointsMatrix.fromList(List.filled(16, 1.0));
final _kpStandUp = JointsMatrix.fromList(List.filled(16, 20.0));
final _kdStandUp = JointsMatrix.fromList(List.filled(16, 2.0));
final _kpSitDown = JointsMatrix.fromList(List.filled(16, 30.0));
final _kdSitDown = JointsMatrix.fromList(List.filled(16, 3.0));

GainManager _make({void Function(JointsMatrix, JointsMatrix)? onChanged}) =>
    GainManager(
      inferKp: _kpInfer,
      inferKd: _kdInfer,
      standUpKp: _kpStandUp,
      standUpKd: _kdStandUp,
      sitDownKp: _kpSitDown,
      sitDownKd: _kdSitDown,
      onChanged: onChanged,
    );

void main() {
  group('initial state', () {
    test('kp/kd default to infer gains', () {
      final gm = _make();
      expect(identical(gm.kp, _kpInfer), isTrue);
      expect(identical(gm.kd, _kdInfer), isTrue);
    });
  });

  group('applyCommand', () {
    test('Walk → infer gains', () {
      final gm = _make();
      // Force to standUp first so Walk is actually a change
      gm.applyCommand(const A.standUp());
      gm.applyCommand(A.walk(Vector3(1, 0, 0)));
      expect(identical(gm.kp, _kpInfer), isTrue);
      expect(identical(gm.kd, _kdInfer), isTrue);
    });

    test('StandUp → standUp gains', () {
      final gm = _make();
      gm.applyCommand(const A.standUp());
      expect(identical(gm.kp, _kpStandUp), isTrue);
      expect(identical(gm.kd, _kdStandUp), isTrue);
    });

    test('SitDown → sitDown gains', () {
      final gm = _make();
      gm.applyCommand(const A.sitDown());
      expect(identical(gm.kp, _kpSitDown), isTrue);
      expect(identical(gm.kd, _kdSitDown), isTrue);
    });

    test('Idle/Init/Fault/Done do not change gains', () {
      final gm = _make();
      gm.applyCommand(const A.standUp()); // set to standUp
      final kpBefore = gm.kp;
      final kdBefore = gm.kd;

      gm.applyCommand(const A.idle());
      expect(identical(gm.kp, kpBefore), isTrue);

      gm.applyCommand(const A.init());
      expect(identical(gm.kp, kpBefore), isTrue);

      gm.applyCommand(const A.fault('test'));
      expect(identical(gm.kp, kpBefore), isTrue);

      gm.applyCommand(const A.done());
      expect(identical(gm.kp, kpBefore), isTrue);
      expect(identical(gm.kd, kdBefore), isTrue);
    });

    test('same gains → onChanged NOT called (dedup by identical)', () {
      var callCount = 0;
      final gm = _make(onChanged: (_, _) => callCount++);

      // Initial is infer; Walk also maps to infer → no change
      gm.applyCommand(A.walk(Vector3(1, 0, 0)));
      expect(callCount, 0);
    });

    test('different gains → onChanged IS called', () {
      var callCount = 0;
      final gm = _make(onChanged: (_, _) => callCount++);

      gm.applyCommand(const A.standUp());
      expect(callCount, 1);
    });
  });

  group('switchGains', () {
    test('updates all six gain sets', () {
      final gm = _make();
      final newKp = JointsMatrix.fromList(List.filled(16, 99.0));
      final newKd = JointsMatrix.fromList(List.filled(16, 9.0));

      gm.switchGains(
        inferKp: newKp,
        inferKd: newKd,
        standUpKp: newKp,
        standUpKd: newKd,
        sitDownKp: newKp,
        sitDownKd: newKd,
      );

      expect(identical(gm.inferKp, newKp), isTrue);
      expect(identical(gm.inferKd, newKd), isTrue);
      expect(identical(gm.standUpKp, newKp), isTrue);
      expect(identical(gm.standUpKd, newKd), isTrue);
      expect(identical(gm.sitDownKp, newKp), isTrue);
      expect(identical(gm.sitDownKd, newKd), isTrue);
    });

    test('after switchGains, applyCommand uses new gains', () {
      final gm = _make();
      final newStandUpKp = JointsMatrix.fromList(List.filled(16, 55.0));
      final newStandUpKd = JointsMatrix.fromList(List.filled(16, 5.5));

      gm.switchGains(
        inferKp: _kpInfer,
        inferKd: _kdInfer,
        standUpKp: newStandUpKp,
        standUpKd: newStandUpKd,
        sitDownKp: _kpSitDown,
        sitDownKd: _kdSitDown,
      );

      gm.applyCommand(const A.standUp());
      expect(identical(gm.kp, newStandUpKp), isTrue);
      expect(identical(gm.kd, newStandUpKd), isTrue);
    });
  });

  group('Gesture command', () {
    test('uses standUp gains', () {
      final gm = _make();
      gm.applyCommand(const A.gesture('bow'));
      expect(identical(gm.kp, _kpStandUp), isTrue);
      expect(identical(gm.kd, _kdStandUp), isTrue);
    });
  });
}
