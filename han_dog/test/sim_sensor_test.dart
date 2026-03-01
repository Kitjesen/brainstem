import 'dart:math' show pi;

import 'package:han_dog/src/server/sim_sensor.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// JointsMatrix 没有实现 operator==，用 values 逐元素比较。
Matcher matrixEquals(JointsMatrix expected) =>
    predicate<JointsMatrix>(
      (actual) => actual.values.length == expected.values.length &&
          List.generate(
            actual.values.length,
            (i) => (actual.values[i] - expected.values[i]).abs() < 1e-9,
          ).every((ok) => ok),
      'JointsMatrix values equal to ${expected.values}',
    );

void main() {
  final standingPose = JointsMatrix(
    0, -0.64, 1.6,
    0, 0.64, -1.6,
    0, 0.64, -1.6,
    0, -0.64, 1.6,
    0, 0, 0, 0,
  );

  group('initialization', () {
    late SimSensorService sim;

    setUp(() {
      sim = SimSensorService(standingPose: standingPose);
    });

    test('position equals standingPose', () {
      expect(sim.position.values, standingPose.values);
    });

    test('velocity is zero', () {
      expect(sim.velocity, matrixEquals(.zero()));
    });

    test('torque is zero', () {
      expect(sim.torque, matrixEquals(.zero()));
    });

    test('gyroscope is zero', () {
      expect(sim.gyroscope, Vector3.zero());
    });

    test('quaternion is identity', () {
      expect(sim.quaternion.x, 0.0);
      expect(sim.quaternion.y, 0.0);
      expect(sim.quaternion.z, 0.0);
      expect(sim.quaternion.w, 1.0);
    });

    test('projectedGravity with identity quaternion is (0,0,-1)', () {
      final g = sim.projectedGravity;
      expect(g.x, closeTo(0.0, 1e-9));
      expect(g.y, closeTo(0.0, 1e-9));
      expect(g.z, closeTo(-1.0, 1e-9));
    });

    test('initialPosition equals standingPose', () {
      expect(sim.initialPosition.values, standingPose.values);
    });

    test('initialVelocity is zero', () {
      expect(sim.initialVelocity, matrixEquals(.zero()));
    });

    test('initialGyroscope is zero', () {
      expect(sim.initialGyroscope, Vector3.zero());
    });

    test('initialProjectedGravity is (0,0,-1)', () {
      expect(sim.initialProjectedGravity.x, closeTo(0.0, 1e-9));
      expect(sim.initialProjectedGravity.y, closeTo(0.0, 1e-9));
      expect(sim.initialProjectedGravity.z, closeTo(-1.0, 1e-9));
    });
  });

  group('injectSim', () {
    late SimSensorService sim;

    setUp(() {
      sim = SimSensorService(standingPose: standingPose);
    });

    test('updates all mutable fields', () {
      final newGyro = Vector3(1.0, 2.0, 3.0);
      final newQuat = Quaternion.axisAngle(Vector3(0, 0, 1), 0.5);
      final newPos = JointsMatrix.fromList(List.filled(16, 1.0));
      final newVel = JointsMatrix.fromList(List.filled(16, 0.5));
      final newTorque = JointsMatrix.fromList(List.filled(16, 0.1));

      sim.injectSim(
        gyroscope: newGyro,
        quaternion: newQuat,
        position: newPos,
        velocity: newVel,
        torque: newTorque,
      );

      expect(sim.gyroscope, newGyro);
      expect(sim.quaternion.x, newQuat.x);
      expect(sim.quaternion.y, newQuat.y);
      expect(sim.quaternion.z, newQuat.z);
      expect(sim.quaternion.w, newQuat.w);
      expect(sim.position, matrixEquals(newPos));
      expect(sim.velocity, matrixEquals(newVel));
      expect(sim.torque, matrixEquals(newTorque));
    });

    test('torque defaults to zero when omitted', () {
      sim.injectSim(
        gyroscope: Vector3.zero(),
        quaternion: Quaternion.identity(),
        position: .zero(),
        velocity: .zero(),
      );
      expect(sim.torque, matrixEquals(.zero()));
    });

    test('initial values remain unchanged after inject', () {
      sim.injectSim(
        gyroscope: Vector3(9, 9, 9),
        quaternion: Quaternion.axisAngle(Vector3(1, 0, 0), 1.0),
        position: JointsMatrix.fromList(List.filled(16, 99.0)),
        velocity: JointsMatrix.fromList(List.filled(16, 88.0)),
      );
      expect(sim.initialPosition.values, standingPose.values);
      expect(sim.initialVelocity, matrixEquals(.zero()));
      expect(sim.initialGyroscope, Vector3.zero());
    });

    test('projectedGravity recomputed from new quaternion', () {
      // 90° rotation around X axis
      final q = Quaternion.axisAngle(Vector3(1, 0, 0), pi / 2);
      sim.injectSim(
        gyroscope: Vector3.zero(),
        quaternion: q,
        position: .zero(),
        velocity: .zero(),
      );
      final g = sim.projectedGravity;
      // vector_math rotate convention: result magnitude should be 1
      expect(g.length, closeTo(1.0, 1e-6));
      expect(g.x, closeTo(0.0, 1e-6));
      // Verify rotation changed gravity direction (no longer (0,0,-1))
      expect(g.z.abs(), lessThan(0.01));
    });

    test('discards frame when gyroscope contains NaN', () {
      sim.injectSim(
        gyroscope: Vector3(double.nan, 0, 0),
        quaternion: Quaternion.identity(),
        position: JointsMatrix.fromList(List.filled(16, 99.0)),
        velocity: .zero(),
      );
      // Position should remain at standingPose (initial value)
      expect(sim.position.values, standingPose.values);
      expect(sim.gyroscope, Vector3.zero());
    });

    test('discards frame when quaternion contains Infinity', () {
      sim.injectSim(
        gyroscope: Vector3.zero(),
        quaternion: Quaternion(double.infinity, 0, 0, 1),
        position: JointsMatrix.fromList(List.filled(16, 99.0)),
        velocity: .zero(),
      );
      expect(sim.position.values, standingPose.values);
    });

    test('discards frame when position contains NaN', () {
      final nanPos = List.filled(16, 0.0);
      nanPos[5] = double.nan;
      sim.injectSim(
        gyroscope: Vector3.zero(),
        quaternion: Quaternion.identity(),
        position: JointsMatrix.fromList(nanPos),
        velocity: .zero(),
      );
      expect(sim.position.values, standingPose.values);
    });

    test('discards frame when velocity contains Infinity', () {
      final infVel = List.filled(16, 0.0);
      infVel[0] = double.negativeInfinity;
      sim.injectSim(
        gyroscope: Vector3.zero(),
        quaternion: Quaternion.identity(),
        position: .zero(),
        velocity: JointsMatrix.fromList(infVel),
      );
      // Velocity should remain at initial zero
      expect(sim.velocity, matrixEquals(.zero()));
    });

    test('discards frame when torque contains NaN', () {
      final nanTorque = List.filled(16, 0.0);
      nanTorque[10] = double.nan;
      sim.injectSim(
        gyroscope: Vector3(1, 2, 3),
        quaternion: Quaternion.identity(),
        position: JointsMatrix.fromList(List.filled(16, 1.0)),
        velocity: .zero(),
        torque: JointsMatrix.fromList(nanTorque),
      );
      // Everything should remain at initial values
      expect(sim.gyroscope, Vector3.zero());
      expect(sim.position.values, standingPose.values);
      expect(sim.torque, matrixEquals(.zero()));
    });

    test('accepts valid frame after rejecting invalid one', () {
      // First: invalid frame
      sim.injectSim(
        gyroscope: Vector3(double.nan, 0, 0),
        quaternion: Quaternion.identity(),
        position: JointsMatrix.fromList(List.filled(16, 99.0)),
        velocity: .zero(),
      );
      expect(sim.position.values, standingPose.values);

      // Second: valid frame
      final validPos = JointsMatrix.fromList(List.filled(16, 2.0));
      sim.injectSim(
        gyroscope: Vector3(1, 2, 3),
        quaternion: Quaternion.identity(),
        position: validPos,
        velocity: .zero(),
      );
      expect(sim.position, matrixEquals(validPos));
      expect(sim.gyroscope, Vector3(1, 2, 3));
    });
  });
}
