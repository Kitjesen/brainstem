import 'dart:convert';
import 'dart:io';

import 'package:thunder/thunder.dart';
import 'package:thunder/src/app/config.dart';
import 'package:test/test.dart';

Map<String, dynamic> profileJson(String name) => {
  'name': name,
  'modelPath': 'model/$name.onnx',
  'standingPose': List.filled(16, 0.12),
  'sittingPose': List.filled(16, 0.0),
  'inferKp': List.filled(16, 80.0),
  'inferKd': List.filled(16, 6.93),
  'standUpKp': List.filled(16, 200.0),
  'standUpKd': List.filled(16, 8.0),
  'sitDownKp': List.filled(16, 200.0),
  'sitDownKd': List.filled(16, 8.0),
  'standUpCounts': 150,
  'sitDownCounts': 150,
};

void main() {
  late OperatorModeSlots slots;
  late Map<String, RobotProfile> profiles;
  setUp(() {
    slots = OperatorModeSlots.fromJson({
      'flat': 'new_flat',
      'stairs': 'new_stairs',
    });
    profiles = {
      for (final name in slots.profileNames)
        name: RobotProfile.fromJson(profileJson(name)),
    };
  });

  test(
    'arbitrary profile names define both slots and default is always flat',
    () {
      expect(slots.profileNames, ['new_flat', 'new_stairs']);
      expect(slots.defaultProfile, 'new_flat');
      slots.validateProfiles(profiles);
      final replaced = OperatorModeSlots.fromJson({
        'flat': 'another_flat',
        'stairs': 'new_stairs',
      });
      expect(replaced.defaultProfile, 'another_flat');
      expect(replaced.profileNames, ['another_flat', 'new_stairs']);
      expect(slots.flat, 'new_flat');
    },
  );

  final invalid = <Object?>[
    null,
    [],
    'flat',
    {},
    {'flat': 'a'},
    {'stairs': 'b'},
    {'flat': 'a', 'stairs': 'b', 'archive': 'c'},
    {'flat': '', 'stairs': 'b'},
    {'flat': 'a', 'stairs': ' '},
    {'flat': ' a', 'stairs': 'b'},
    {'flat': 'a', 'stairs': 'b '},
    {'flat': 1, 'stairs': 'b'},
    {'flat': 'a', 'stairs': null},
    {'flat': 'same', 'stairs': 'same'},
  ];
  for (var i = 0; i < invalid.length; i++) {
    test('reject malformed binding $i, no fallback', () {
      expect(
        () => OperatorModeSlots.fromJson(invalid[i]),
        throwsFormatException,
      );
    });
  }

  test('missing or misnamed profiles are rejected', () {
    profiles.remove('new_stairs');
    expect(() => slots.validateProfiles(profiles), throwsStateError);
    profiles['new_stairs'] = RobotProfile.fromJson(profileJson('wrong_name'));
    expect(() => slots.validateProfiles(profiles), throwsStateError);
  });

  test('optional high platform preserves legacy and null bindings', () {
    for (final json in [
      {'flat': 'new_flat', 'stairs': 'new_stairs'},
      {'flat': 'new_flat', 'stairs': 'new_stairs', 'high_platform': null},
    ]) {
      final parsed = OperatorModeSlots.fromJson(json);
      expect(parsed.highPlatform, isNull);
      expect(parsed.profileNames, ['new_flat', 'new_stairs']);
      parsed.validateProfiles(profiles);
    }
    final parsed = OperatorModeSlots.fromJson({
      'flat': 'new_flat',
      'stairs': 'new_stairs',
      'high_platform': 'platform',
    });
    expect(parsed.highPlatform, 'platform');
    expect(parsed.defaultProfile, 'new_flat');
    expect(parsed.profileNames, ['new_flat', 'new_stairs', 'platform']);
    expect(() => parsed.validateProfiles(profiles), throwsStateError);
    profiles['platform'] = RobotProfile.fromJson(profileJson('wrong_name'));
    expect(() => parsed.validateProfiles(profiles), throwsStateError);
    profiles['platform'] = RobotProfile.fromJson(profileJson('platform'));
    parsed.validateProfiles(profiles);
  });

  for (final value in [
    '',
    ' ',
    ' platform',
    'platform ',
    1,
    <Object?>[],
    'new_flat',
    'new_stairs',
  ]) {
    test('reject invalid or duplicate high platform binding $value', () {
      expect(
        () => OperatorModeSlots.fromJson({
          'flat': 'new_flat',
          'stairs': 'new_stairs',
          'high_platform': value,
        }),
        throwsFormatException,
      );
    });
  }

  for (final field in [
    'standingPose',
    'sittingPose',
    'standUpKp',
    'standUpKd',
    'sitDownKp',
    'sitDownKd',
    'standUpCounts',
    'sitDownCounts',
  ]) {
    test('high platform rejects mismatched $field', () {
      final parsed = OperatorModeSlots.fromJson({
        'flat': 'new_flat',
        'stairs': 'new_stairs',
        'high_platform': 'platform',
      });
      final json = profileJson('platform');
      if (json[field] is List<double>) {
        (json[field] as List<double>)[2] += 0.01;
      } else {
        json[field] = 151;
      }
      profiles['platform'] = RobotProfile.fromJson(json);
      expect(() => parsed.validateProfiles(profiles), throwsStateError);
    });
  }

  for (final field in [
    'standingPose',
    'sittingPose',
    'standUpKp',
    'standUpKd',
    'sitDownKp',
    'sitDownKd',
  ]) {
    test('reject mismatched $field without changing parameters', () {
      final json = profileJson('new_stairs');
      final values = json[field] as List<double>;
      values[2] += 0.01;
      profiles['new_stairs'] = RobotProfile.fromJson(json);
      expect(() => slots.validateProfiles(profiles), throwsStateError);
      expect(
        values[2],
        (profileJson('new_stairs')[field] as List<double>)[2] + 0.01,
      );
    });
  }
  for (final field in ['standUpCounts', 'sitDownCounts']) {
    test('reject mismatched $field', () {
      profiles['new_stairs'] = RobotProfile.fromJson(
        profileJson('new_stairs')..[field] = 151,
      );
      expect(() => slots.validateProfiles(profiles), throwsStateError);
    });
  }

  test('different Walk gains and layouts are not silently unified', () {
    final json = profileJson('new_stairs');
    json['inferKp'] = List.filled(16, 120.0);
    json['observationLayout'] = 'thunderCts53';
    profiles['new_stairs'] = RobotProfile.fromJson(json);
    slots.validateProfiles(profiles);
    expect(profiles['new_stairs']!.inferKp.values, everyElement(120.0));
    expect(profiles['new_flat']!.inferKp.values, everyElement(80.0));
  });

  test(
    'load file and reject missing or invalid file instead of archive fallback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'operator_modes_',
      );
      try {
        final file = File('${directory.path}/operator_modes.json');
        await expectLater(
          OperatorModeSlots.load(file.path),
          throwsA(isA<FileSystemException>()),
        );
        await file.writeAsString('{invalid');
        await expectLater(
          OperatorModeSlots.load(file.path),
          throwsFormatException,
        );
        await file.writeAsString(
          jsonEncode({'flat': 'new_flat', 'stairs': 'new_stairs'}),
        );
        final loaded = await OperatorModeSlots.load(file.path);
        expect(loaded.defaultProfile, 'new_flat');
        loaded.validateProfiles(profiles);
        await file.writeAsString(
          jsonEncode({'flat': 'next_flat', 'stairs': 'next_stairs'}),
        );
        expect(loaded.profileNames, ['new_flat', 'new_stairs']);
        expect(
          (await OperatorModeSlots.load(file.path)).defaultProfile,
          'next_flat',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('config path override selects file, not legacy default profile', () {
    final config = ThunderConfig(
      environment: {
        'THUNDER_OPERATOR_MODES': 'config/demo_modes.json',
        'THUNDER_DEFAULT_PROFILE': 'old_archived_model',
      },
    );
    expect(config.operatorModesPath, 'config/demo_modes.json');
    expect(
      ThunderConfig(environment: {}).operatorModesPath,
      'thunder/config/operator_modes.json',
    );
    expect(slots.defaultProfile, 'new_flat');
  });
}
