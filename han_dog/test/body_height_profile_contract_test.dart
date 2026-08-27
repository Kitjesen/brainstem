import 'dart:convert';
import 'dart:io';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart'
    show SingleFrameHeightObservationBuilder;
import 'package:test/test.dart';

const _safeStandPose = [
  -0.1,
  -0.8,
  1.8,
  0.1,
  0.8,
  -1.8,
  0.1,
  0.8,
  -1.8,
  -0.1,
  -0.8,
  1.8,
  0.0,
  0.0,
  0.0,
  0.0,
];

const _trainedPolicyPose = [
  -0.1,
  -1.1,
  2.6,
  0.1,
  1.1,
  -2.6,
  0.1,
  1.1,
  -2.6,
  -0.1,
  -1.1,
  2.6,
  0.0,
  0.0,
  0.0,
  0.0,
];

File _profileFile(String name) {
  for (final path in ['profiles/$name.json', 'han_dog/profiles/$name.json']) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  throw StateError(
    'Could not find $name.json from repository-relative test paths',
  );
}

void main() {
  const expectations = {
    'thunder_h15': (
      inputName: 'policy_obs',
      historySize: 1,
      inputSize: 58,
      modelPath: 'model/thunder_h15_model10400.onnx',
      sha256:
          'ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4',
    ),
    'thunder_h18': (
      inputName: 'policy_history',
      historySize: 10,
      inputSize: 580,
      modelPath: 'model/thunder_h18_model5000.onnx',
      sha256:
          'd632413aa9ddf16b6c795377bdbbef69c454ba1cc77f8acb7d560f381cd84296',
    ),
  };

  for (final entry in expectations.entries) {
    final name = entry.key;
    final expected = entry.value;
    test('$name preserves the body-height profile contract', () {
      final raw =
          jsonDecode(_profileFile(name).readAsStringSync())
              as Map<String, dynamic>;
      final profile = RobotProfile.fromJson(raw);
      final builder = profile.toObservationBuilder();

      expect(raw['standingPose'], _safeStandPose);
      expect(raw['standUpPose'], _safeStandPose);
      expect(raw['policyDefaultPose'], _trainedPolicyPose);

      expect(profile.standingPose.values, _safeStandPose);
      expect(profile.standUpPose.values, _safeStandPose);
      expect(profile.policyDefaultPose.values, _trainedPolicyPose);
      expect(builder.standingPose.values, _trainedPolicyPose);

      expect(profile.bodyHeightCommand, 0.40);
      expect(profile.minBodyHeightCommand, 0.20);
      expect(profile.maxBodyHeightCommand, 0.54);
      expect(profile.observationType, 'bodyHeight');
      expect(builder.tensorSize, 58);
      expect(profile.inputName, expected.inputName);
      expect(profile.modelPath, expected.modelPath);
      expect(raw['_historySize'], expected.historySize);
      expect(raw['_onnxSha256'], expected.sha256);
      expect(builder.tensorSize * expected.historySize, expected.inputSize);
    });
  }

  test('single_frame_height_v2 matches the accepted deployment contract', () {
    final raw =
        jsonDecode(_profileFile('single_frame_height_v2').readAsStringSync())
            as Map<String, dynamic>;
    final profile = RobotProfile.fromJson(raw);
    final builder = profile.toObservationBuilder();

    expect(profile.observationType, 'singleFrameHeight');
    expect(builder, isA<SingleFrameHeightObservationBuilder>());
    expect(builder.tensorSize, 58);
    expect(profile.inputName, 'obs');
    expect(profile.bodyHeightCommand, 0.375);
    expect(profile.minBodyHeightCommand, 0.25);
    expect(profile.maxBodyHeightCommand, 0.50);
    expect(profile.bodyHeightRateLimit, 0.05);
    expect(profile.velocityCommandMin, (-0.5, -0.3, -0.3));
    expect(profile.velocityCommandMax, (0.5, 0.3, 0.3));
    expect(raw['_historySize'], 1);
    expect(
      raw['_onnxSha256'],
      '318bff03d1b765f30553bf5aea85a2b413f58a8a2078eae830a097e6475dffb5',
    );
    expect(profile.modelPath, 'model/single_frame_height_v2_policy.onnx');
    expect(_profileFile('single_frame_height_v2').existsSync(), isTrue);
    expect(File(profile.modelPath).lengthSync(), 787237);
  });
}
