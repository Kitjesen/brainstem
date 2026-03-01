import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog/src/server/proto_convert.dart';
import 'package:han_dog_message/han_dog_message.dart' as proto;
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('Vector3', () {
    test('VM → Proto round-trip', () {
      final v = vm.Vector3(1.5, -2.3, 0.7);
      final p = v.toProto();
      // Proto uses float32, so closeTo for precision
      expect(p.x, closeTo(1.5, 1e-6));
      expect(p.y, closeTo(-2.3, 1e-6));
      expect(p.z, closeTo(0.7, 1e-6));

      final back = p.toVM();
      expect(back.x, closeTo(v.x, 1e-6));
      expect(back.y, closeTo(v.y, 1e-6));
      expect(back.z, closeTo(v.z, 1e-6));
    });

    test('zero vector', () {
      final v = vm.Vector3.zero();
      final p = v.toProto();
      expect(p.x, 0.0);
      expect(p.y, 0.0);
      expect(p.z, 0.0);
    });
  });

  group('Quaternion', () {
    test('Hamilton convention (w,x,y,z)', () {
      final q = vm.Quaternion(0.1, 0.2, 0.3, 0.9); // x, y, z, w
      final p = q.toProto();
      expect(p.w, q.w); // 0.9
      expect(p.x, q.x); // 0.1
      expect(p.y, q.y); // 0.2
      expect(p.z, q.z); // 0.3
    });

    test('identity quaternion', () {
      final q = vm.Quaternion.identity();
      final p = q.toProto();
      expect(p.w, 1.0);
      expect(p.x, 0.0);
      expect(p.y, 0.0);
      expect(p.z, 0.0);
    });
  });

  group('JointsMatrix', () {
    test('16 values → Matrix4 Proto', () {
      final values = List.generate(16, (i) => i * 0.1);
      final m = JointsMatrix.fromList(values);
      final p = m.toProto();
      expect(p.values, values);
    });

    test('zero matrix', () {
      final m = JointsMatrix.zero();
      final p = m.toProto();
      expect(p.values, List.filled(16, 0.0));
    });
  });

  group('Command', () {
    test('idle', () {
      const cmd = Command.idle();
      final p = cmd.toProto();
      expect(p.hasIdle(), isTrue);
    });

    test('standUp', () {
      const cmd = Command.standUp();
      final p = cmd.toProto();
      expect(p.hasStandUp(), isTrue);
    });

    test('sitDown', () {
      const cmd = Command.sitDown();
      final p = cmd.toProto();
      expect(p.hasSitDown(), isTrue);
    });

    test('walk preserves direction', () {
      final cmd = Command.walk(vm.Vector3(1, 2, 3));
      final p = cmd.toProto();
      expect(p.hasWalk(), isTrue);
      expect(p.walk.x, 1.0);
      expect(p.walk.y, 2.0);
      expect(p.walk.z, 3.0);
    });
  });

  group('History', () {
    test('toProto includes all fields', () {
      final h = History(
        gyroscope: vm.Vector3(1, 2, 3),
        projectedGravity: vm.Vector3(0, 0, -1),
        command: const Command.standUp(),
        jointPosition: JointsMatrix.fromList(List.filled(16, 0.5)),
        jointVelocity: JointsMatrix.fromList(List.filled(16, 0.1)),
        action: JointsMatrix.fromList(List.filled(16, 0.2)),
        nextAction: JointsMatrix.fromList(List.filled(16, 0.3)),
      );
      final p = h.toProto();

      expect(p.gyroscope.x, 1.0);
      expect(p.gyroscope.y, 2.0);
      expect(p.gyroscope.z, 3.0);
      expect(p.projectedGravity.z, -1.0);
      expect(p.command.hasStandUp(), isTrue);
      expect(p.jointPosition.values.first, 0.5);
      expect(p.jointVelocity.values.first, 0.1);
      expect(p.action.values.first, 0.2);
      expect(p.nextAction.values.first, 0.3);
    });

    test('toProto with timestamp present', () {
      final h = History.zero();
      final p = h.toProto(timestamp: proto.Duration());

      expect(p.hasTimestamp(), isTrue);
    });

    test('toProto without timestamp', () {
      final h = History.zero();
      final p = h.toProto();
      expect(p.hasTimestamp(), isFalse);
    });
  });

  group('imuSnapshot', () {
    test('builds Imu proto from service', () {
      final imu = _FakeImu(
        gyroscope: vm.Vector3(0.1, 0.2, 0.3),
        projectedGravity: vm.Vector3(0, 0, -1),
      );
      final q = vm.Quaternion.identity();
      final p = imuSnapshot(imu, quaternion: q);

      // Proto uses float32, so closeTo for precision
      expect(p.gyroscope.x, closeTo(0.1, 1e-6));
      expect(p.gyroscope.y, closeTo(0.2, 1e-6));
      expect(p.gyroscope.z, closeTo(0.3, 1e-6));
      expect(p.quaternion.w, closeTo(1.0, 1e-6));
    });
  });

  group('jointSnapshot', () {
    test('builds Joint proto from service', () {
      final joint = _FakeJoint(
        position: JointsMatrix.fromList(List.filled(16, 1.0)),
        velocity: JointsMatrix.fromList(List.filled(16, 0.5)),
      );
      final p = jointSnapshot(joint);

      expect(p.allJoints.position.values.first, 1.0);
      expect(p.allJoints.velocity.values.first, 0.5);
      expect(p.allJoints.torque.values.first, 0.0); // default zero
    });

    test('with explicit torque', () {
      final joint = _FakeJoint(
        position: JointsMatrix.zero(),
        velocity: JointsMatrix.zero(),
      );
      final torque = JointsMatrix.fromList(List.filled(16, 0.3));
      final p = jointSnapshot(joint, torque: torque);

      expect(p.allJoints.torque.values.first, 0.3);
    });
  });
}

// ── Minimal fakes for snapshot helpers ─────────────────────────

class _FakeImu implements ImuService {
  @override
  final vm.Vector3 gyroscope;
  @override
  final vm.Vector3 projectedGravity;
  @override
  vm.Vector3 get initialGyroscope => vm.Vector3.zero();
  @override
  vm.Vector3 get initialProjectedGravity => vm.Vector3(0, 0, -1);

  _FakeImu({required this.gyroscope, required this.projectedGravity});
}

class _FakeJoint implements JointService {
  @override
  final JointsMatrix position;
  @override
  final JointsMatrix velocity;
  @override
  JointsMatrix get initialPosition => .zero();
  @override
  JointsMatrix get initialVelocity => .zero();

  _FakeJoint({required this.position, required this.velocity});
}
