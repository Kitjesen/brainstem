import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class _Imu extends Mock implements ImuService {}

class _Joint extends Mock implements JointService {}

void main() {
  test('accepted V2 ONNX loads and runs with one 58D frame', () async {
    final raw =
        jsonDecode(
              File(
                'han_dog/profiles/single_frame_height_v2.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final profile = RobotProfile.fromJson(raw);
    final builder = profile.toObservationBuilder();
    final inferredHistory = await inferHistorySizeFromModel(
      modelPath: profile.modelPath,
      tensorSize: builder.tensorSize,
    );
    final inferredInput = await inferInputNameFromModel(
      modelPath: profile.modelPath,
    );

    expect(inferredHistory, 1);
    expect(inferredInput, 'obs');

    final imu = _Imu();
    final joint = _Joint();
    final pose = profile.policyDefaultPose;
    when(() => imu.initialGyroscope).thenReturn(Vector3.zero());
    when(
      () => imu.initialProjectedGravity,
    ).thenReturn(Vector3(0, 0, -1));
    when(() => imu.gyroscope).thenReturn(Vector3.zero());
    when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
    when(() => joint.initialPosition).thenReturn(pose);
    when(() => joint.initialVelocity).thenReturn(JointsMatrix.zero());
    when(() => joint.position).thenReturn(pose);
    when(() => joint.velocity).thenReturn(JointsMatrix.zero());

    final clock = StreamController<void>.broadcast();
    final brain = Brain(
      historySize: 1,
      imu: imu,
      joint: joint,
      clock: clock,
      standingPose: profile.standUpPose,
      sittingPose: profile.sittingPose,
      observationBuilder: builder,
      bodyHeightCommand: profile.bodyHeightCommand,
      minBodyHeightCommand: profile.minBodyHeightCommand,
      maxBodyHeightCommand: profile.maxBodyHeightCommand,
      initialHistory: History(
        gyroscope: Vector3.zero(),
        projectedGravity: Vector3(0, 0, -1),
        command: const Command.idle(),
        bodyHeightCommand: profile.bodyHeightCommand,
        jointPosition: pose,
        jointVelocity: JointsMatrix.zero(),
        action: pose,
        nextAction: pose,
      ),
    );
    addTearDown(() async {
      brain.dispose();
      await clock.close();
    });

    await brain.loadModel(profile.modelPath, inputName: profile.inputName);
    final action = brain.walk.inferOnce();

    expect(brain.isModelLoaded, isTrue);
    expect(brain.walk.lastObservation, hasLength(58));
    expect(brain.walk.lastObservation!.sublist(6, 10), [0, 0, 0, 0.375]);
    expect(action.values, hasLength(16));
    expect(action.hasNonFinite, isFalse);
    expect(brain.lastInferenceUs, greaterThan(0));
  });
}
