import 'dart:convert';
import 'dart:io';

import 'robot_profile.dart';

/// Frozen at startup: R2 selects only these profiles and boot always uses flat.
class OperatorModeSlots {
  final String flat;
  final String stairs;
  final String? highPlatform;

  const OperatorModeSlots._(this.flat, this.stairs, this.highPlatform);

  factory OperatorModeSlots.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json.keys.any(
          (key) => !const {'flat', 'stairs', 'high_platform'}.contains(key),
        ) ||
        !json.containsKey('flat') ||
        !json.containsKey('stairs')) {
      throw const FormatException(
        'Operator modes require flat and stairs, with optional high_platform',
      );
    }
    String name(String slot) {
      final value = json[slot];
      if (value is! String || value.isEmpty || value.trim() != value) {
        throw FormatException(
          'Operator slot $slot must be a nonempty profile name',
        );
      }
      return value;
    }

    final flat = name('flat');
    final stairs = name('stairs');
    final highPlatform = json['high_platform'] == null
        ? null
        : name('high_platform');
    final names = [flat, stairs, if (highPlatform != null) highPlatform];
    if (names.toSet().length != names.length) {
      throw const FormatException(
        'Operator slots must reference different profiles',
      );
    }
    return OperatorModeSlots._(flat, stairs, highPlatform);
  }

  static Future<OperatorModeSlots> load(String path) async =>
      OperatorModeSlots.fromJson(jsonDecode(await File(path).readAsString()));

  String get defaultProfile => flat;
  List<String> get profileNames => [
    flat,
    stairs,
    if (highPlatform != null) highPlatform!,
  ];

  void validateProfiles(Map<String, RobotProfile> profiles) {
    for (final name in profileNames) {
      if (!profiles.containsKey(name) || profiles[name]!.name != name) {
        throw StateError('Operator slot profile is missing or misnamed: $name');
      }
    }
    final a = profiles[flat]!;
    for (final name in profileNames.skip(1)) {
      final b = profiles[name]!;
      final pairs = [
        ('standingPose', a.standingPose, b.standingPose),
        ('sittingPose', a.sittingPose, b.sittingPose),
        ('standUpKp', a.standUpKp, b.standUpKp),
        ('standUpKd', a.standUpKd, b.standUpKd),
        ('sitDownKp', a.sitDownKp, b.sitDownKp),
        ('sitDownKd', a.sitDownKd, b.sitDownKd),
      ];
      for (final pair in pairs) {
        for (var i = 0; i < 16; i++) {
          if (pair.$2.values[i] != pair.$3.values[i]) {
            throw StateError(
              'Operator slots disagree on ${pair.$1}[$i]; do not change training parameters to force a match',
            );
          }
        }
      }
      if (a.standUpCounts != b.standUpCounts ||
          a.sitDownCounts != b.sitDownCounts) {
        throw StateError(
          'Operator slots require matching standUpCounts and sitDownCounts',
        );
      }
    }
  }
}
