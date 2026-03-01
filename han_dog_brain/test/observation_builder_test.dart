import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

// JointsMatrix values layout (16 joints):
//   [0]frHip  [1]frThigh  [2]frCalf
//   [3]flHip  [4]flThigh  [5]flCalf
//   [6]rrHip  [7]rrThigh  [8]rrCalf
//   [9]rlHip [10]rlThigh [11]rlCalf
//   [12]frFoot [13]flFoot [14]rrFoot [15]rlFoot
//
// discardFoot() zeroes indices 12-15.
// scale(hip, thigh, calf, foot) applies per joint-type.

void main() {
  // standingPose: each leg has hip=0.1, thigh=0.2, calf=0.3, foot=0.0
  final standingPose = JointsMatrix.fromList([
    0.1, 0.2, 0.3, // fr
    0.1, 0.2, 0.3, // fl
    0.1, 0.2, 0.3, // rr
    0.1, 0.2, 0.3, // rl
    0.0, 0.0, 0.0, 0.0, // feet
  ]);

  final builder = StandardObservationBuilder(
    standingPose: standingPose,
    imuGyroscopeScale: 0.25,
    jointVelocityScale: (0.05, 0.1, 0.2, 0.5),
    actionScale: (0.125, 0.25, 0.25, 5.0),
  );

  History makeHistory({
    Vector3? gyroscope,
    Vector3? projectedGravity,
    Command? command,
    JointsMatrix? jointPosition,
    JointsMatrix? jointVelocity,
    JointsMatrix? action,
  }) =>
      History(
        gyroscope: gyroscope ?? Vector3.zero(),
        projectedGravity: projectedGravity ?? Vector3(0, 0, -1),
        command: command ?? const Command.idle(),
        jointPosition: jointPosition ?? JointsMatrix.zero(),
        jointVelocity: jointVelocity ?? JointsMatrix.zero(),
        action: action ?? JointsMatrix.zero(),
        nextAction: JointsMatrix.zero(),
      );

  group('tensorSize', () {
    test('is 57', () {
      expect(builder.tensorSize, 57);
    });

    test('build() returns exactly tensorSize elements', () {
      expect(builder.build(makeHistory()).length, builder.tensorSize);
    });
  });

  group('field layout', () {
    // gyroscope section: out[0..2]
    test('out[0-2] = gyroscope × imuGyroscopeScale', () {
      final gyro = Vector3(1.0, 2.0, 4.0); // Vector3 is float32
      final out = builder.build(makeHistory(gyroscope: gyro));

      expect(out[0], closeTo(1.0 * 0.25, 1e-6));
      expect(out[1], closeTo(2.0 * 0.25, 1e-6));
      expect(out[2], closeTo(4.0 * 0.25, 1e-6));
    });

    // projectedGravity section: out[3..5]  — Vector3 is float32, use 1e-6
    test('out[3-5] = projectedGravity (unscaled)', () {
      final pg = Vector3(0.1, 0.2, -0.9);
      final out = builder.build(makeHistory(projectedGravity: pg));

      expect(out[3], closeTo(0.1, 1e-6));
      expect(out[4], closeTo(0.2, 1e-6));
      expect(out[5], closeTo(-0.9, 1e-6));
    });

    // direction section: out[6..8]
    test('out[6-8] = WalkCommand.direction', () {
      final dir = Vector3(0.5, -0.3, 0.0); // Vector3 is float32
      final out = builder.build(makeHistory(command: Command.walk(dir)));

      expect(out[6], closeTo(0.5, 1e-6));
      expect(out[7], closeTo(-0.3, 1e-6));
      expect(out[8], closeTo(0.0, 1e-6));
    });

    test('out[6-8] = zero for non-Walk commands', () {
      for (final cmd in [
        const Command.idle(),
        const Command.standUp(),
        const Command.sitDown(),
      ]) {
        final out = builder.build(makeHistory(command: cmd));
        expect(out[6], 0.0, reason: '$cmd dir.x should be 0');
        expect(out[7], 0.0, reason: '$cmd dir.y should be 0');
        expect(out[8], 0.0, reason: '$cmd dir.z should be 0');
      }
    });

    // jointPosition section: out[9..24]
    // Formula: (jointPosition - standingPose).discardFoot()
    // discardFoot() zeroes indices 12-15 (frFoot/flFoot/rrFoot/rlFoot)
    test('out[9-20] = jointPosition delta (hip/thigh/calf), out[21-24] = 0 (feet discarded)', () {
      // Put recognisable values in hip/thigh/calf; put 99 in foot slots
      final delta = JointsMatrix.fromList([
        0.1, 0.2, 0.3, // fr hip/thigh/calf
        0.4, 0.5, 0.6, // fl
        0.7, 0.8, 0.9, // rr
        1.0, 1.1, 1.2, // rl
        99.0, 99.0, 99.0, 99.0, // feet → must become 0 after discardFoot
      ]);
      final jointPos = standingPose + delta;
      final out = builder.build(makeHistory(jointPosition: jointPos));

      // hip/thigh/calf values preserved
      expect(out[9],  closeTo(0.1, 1e-9)); // frHip
      expect(out[10], closeTo(0.2, 1e-9)); // frThigh
      expect(out[11], closeTo(0.3, 1e-9)); // frCalf
      expect(out[12], closeTo(0.4, 1e-9)); // flHip (NOT foot!)
      expect(out[20], closeTo(1.2, 1e-9)); // rlCalf

      // foot indices 12-15 in JointsMatrix → out[21-24]
      expect(out[21], 0.0); // frFoot zeroed
      expect(out[22], 0.0); // flFoot zeroed
      expect(out[23], 0.0); // rrFoot zeroed
      expect(out[24], 0.0); // rlFoot zeroed
    });

    // jointVelocity section: out[25..40]
    // Formula: jointVelocity * jointVelocityScale  (no discardFoot)
    test('out[25-40] = jointVelocity × jointVelocityScale', () {
      final vel = JointsMatrix.fromList(List.filled(16, 1.0));
      final out = builder.build(makeHistory(jointVelocity: vel));

      // hip (indices 0,3,6,9 in JM → out[25,28,31,34]) × 0.05
      expect(out[25], closeTo(0.05, 1e-9)); // frHip
      expect(out[28], closeTo(0.05, 1e-9)); // flHip
      // thigh (indices 1,4,7,10 → out[26,29,32,35]) × 0.1
      expect(out[26], closeTo(0.1, 1e-9));  // frThigh
      // calf (indices 2,5,8,11 → out[27,30,33,36]) × 0.2
      expect(out[27], closeTo(0.2, 1e-9));  // frCalf
      // foot (indices 12-15 → out[37-40]) × 0.5
      expect(out[37], closeTo(0.5, 1e-9));  // frFoot
    });

    // action section: out[41..56]
    // Formula: (action - standingPose) / actionScale  (no discardFoot)
    test('out[41-56] = 0 when action == standingPose', () {
      final out = builder.build(makeHistory(action: standingPose));
      for (int i = 41; i < 57; i++) {
        expect(out[i], closeTo(0.0, 1e-9),
            reason: 'index $i: action==standingPose → 0');
      }
    });

    test('hip action normalized to 1.0 when delta == actionScale.hip', () {
      // Hip indices in JointsMatrix: 0(frHip), 3(flHip), 6(rrHip), 9(rlHip)
      final hipDelta = JointsMatrix.fromList([
        0.125, 0.0, 0.0, // fr: only hip
        0.125, 0.0, 0.0, // fl: only hip
        0.125, 0.0, 0.0, // rr: only hip
        0.125, 0.0, 0.0, // rl: only hip
        0.0, 0.0, 0.0, 0.0, // feet
      ]);
      final action = standingPose + hipDelta;
      final out = builder.build(makeHistory(action: action));

      // out[41+0]=frHip, out[41+3]=flHip, out[41+6]=rrHip, out[41+9]=rlHip
      expect(out[41], closeTo(1.0, 1e-6)); // frHip / 0.125
      expect(out[44], closeTo(1.0, 1e-6)); // flHip / 0.125
      expect(out[47], closeTo(1.0, 1e-6)); // rrHip / 0.125
      expect(out[50], closeTo(1.0, 1e-6)); // rlHip / 0.125
      // thigh/calf/foot stay 0
      expect(out[42], closeTo(0.0, 1e-9)); // frThigh
    });
  });

  group('standingPose / actionScale passthrough', () {
    test('standingPose returns constructor value', () {
      expect(builder.standingPose.values, standingPose.values);
    });

    test('actionScale returns constructor value', () {
      expect(builder.actionScale, (0.125, 0.25, 0.25, 5.0));
    });
  });
}
