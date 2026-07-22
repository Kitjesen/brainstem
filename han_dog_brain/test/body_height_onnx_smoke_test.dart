import 'dart:async';
import 'dart:io';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class _MockImu extends Mock implements ImuService {}

class _MockJoint extends Mock implements JointService {}

void main() {
  late _MockImu imu;
  late _MockJoint joint;

  setUp(() {
    imu = _MockImu();
    joint = _MockJoint();
    when(() => imu.initialGyroscope).thenReturn(Vector3.zero());
    when(() => imu.initialProjectedGravity).thenReturn(Vector3(0, 0, -1));
    when(() => imu.gyroscope).thenReturn(Vector3.zero());
    when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
    when(() => joint.initialPosition).thenReturn(JointsMatrix.zero());
    when(() => joint.initialVelocity).thenReturn(JointsMatrix.zero());
    when(() => joint.position).thenReturn(JointsMatrix.zero());
    when(() => joint.velocity).thenReturn(JointsMatrix.zero());
  });

  Future<void> verifyModel({
    required String path,
    required String expectedInputName,
    required int expectedHistorySize,
    required List<double> expectedRawAction,
  }) async {
    expect(
      await inferHistorySizeFromModel(modelPath: path, tensorSize: 58),
      expectedHistorySize,
    );
    expect(await inferInputNameFromModel(modelPath: path), expectedInputName);

    final clock = StreamController<void>.broadcast();
    final brain = Brain(
      imu: imu,
      joint: joint,
      clock: clock,
      historySize: expectedHistorySize,
      standingPose: JointsMatrix.zero(),
      sittingPose: JointsMatrix.zero(),
      observationBuilder: BodyHeightObservationBuilder(
        standingPose: JointsMatrix.zero(),
      ),
      bodyHeightCommand: 0.35,
      minBodyHeightCommand: 0.20,
      maxBodyHeightCommand: 0.54,
    );
    try {
      await brain.loadModel(path, inputName: expectedInputName);
      expect(brain.isModelLoaded, isTrue);

      final action = brain.walk.inferOnce();
      expect(action.values, hasLength(16));
      expect(action.values.every((value) => value.isFinite), isTrue);
      expect(brain.walk.lastObservation, hasLength(expectedHistorySize * 58));
      final rawAction = brain.walk.fromRealAction(action).values;
      for (var index = 0; index < expectedRawAction.length; index++) {
        expect(
          rawAction[index],
          closeTo(expectedRawAction[index], 2e-5),
          reason: 'raw action mismatch at index $index',
        );
      }
    } finally {
      brain.dispose();
      await clock.close();
    }
  }

  final h15 = Platform.environment['THUNDER_H15_ONNX'];
  test(
    'H15 loads policy_obs [batch,58] and performs finite inference',
    () => verifyModel(
      path: h15!,
      expectedInputName: 'policy_obs',
      expectedHistorySize: 1,
      expectedRawAction: const [
        1.079972625,
        1.088511705,
        -2.138119936,
        -0.283885479,
        -0.7519369125,
        1.781926394,
        -1.468549728,
        -0.7644513249,
        2.348271132,
        0.7077422142,
        0.4247033,
        -1.968237638,
        1.406055689,
        -1.896926999,
        -1.246877193,
        0.7578487992,
      ],
    ),
    skip: h15 == null ? 'THUNDER_H15_ONNX is not set' : false,
  );

  final h18 = Platform.environment['THUNDER_H18_ONNX'];
  test(
    'H18 loads policy_history [batch,580] and performs finite inference',
    () => verifyModel(
      path: h18!,
      expectedInputName: 'policy_history',
      expectedHistorySize: 10,
      expectedRawAction: const [
        0.8223490715,
        0.7065320015,
        -2.155096054,
        -0.1595235169,
        -0.4791309536,
        1.974220991,
        -1.387149096,
        -0.4104833305,
        1.972728014,
        0.8439813256,
        0.3463437557,
        -2.181377172,
        1.805941939,
        -2.038410902,
        -1.002329946,
        0.6443693042,
      ],
    ),
    skip: h18 == null ? 'THUNDER_H18_ONNX is not set' : false,
  );
}
