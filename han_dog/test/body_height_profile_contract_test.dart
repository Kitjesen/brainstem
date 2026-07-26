import 'dart:convert';
import 'dart:io';

import 'package:han_dog/han_dog.dart';
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
  for (final name in ['thunder_h15', 'thunder_h18']) {
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
    });
  }
}
