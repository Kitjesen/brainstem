import 'dart:convert';
import 'dart:io';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

final _log = Logger('han_dog.profile');

/// 机器人策略配置：一套完整的模型 + 姿态 + 增益 + 缩放参数。
class RobotProfile {
  final String name;
  final String description;
  final String modelPath;
  final JointsMatrix standingPose;
  final JointsMatrix sittingPose;
  final int standUpCounts;
  final int sitDownCounts;
  final JointsMatrix inferKp;
  final JointsMatrix inferKd;
  final JointsMatrix standUpKp;
  final JointsMatrix standUpKd;
  final JointsMatrix sitDownKp;
  final JointsMatrix sitDownKd;
  final double imuGyroscopeScale;
  final (double, double, double, double) jointVelocityScale;
  final (double, double, double, double) actionScale;

  const RobotProfile({
    required this.name,
    this.description = '',
    required this.modelPath,
    required this.standingPose,
    required this.sittingPose,
    this.standUpCounts = 150,
    this.sitDownCounts = 150,
    required this.inferKp,
    required this.inferKd,
    required this.standUpKp,
    required this.standUpKd,
    required this.sitDownKp,
    required this.sitDownKd,
    this.imuGyroscopeScale = 0.25,
    this.jointVelocityScale = (0.05, 0.05, 0.05, 0.05),
    this.actionScale = (0.125, 0.25, 0.25, 5.0),
  });

  factory RobotProfile.fromJson(Map<String, dynamic> json) {
    return RobotProfile(
      name: _reqString(json, 'name'),
      description: json['description'] as String? ?? '',
      modelPath: _reqString(json, 'modelPath'),
      standingPose: _joints16(json, 'standingPose'),
      sittingPose: _joints16(json, 'sittingPose'),
      standUpCounts: (json['standUpCounts'] as num?)?.toInt() ?? 150,
      sitDownCounts: (json['sitDownCounts'] as num?)?.toInt() ?? 150,
      inferKp: _joints16(json, 'inferKp'),
      inferKd: _joints16(json, 'inferKd'),
      standUpKp: _joints16(json, 'standUpKp'),
      standUpKd: _joints16(json, 'standUpKd'),
      sitDownKp: _joints16(json, 'sitDownKp'),
      sitDownKd: _joints16(json, 'sitDownKd'),
      imuGyroscopeScale: (json['imuGyroscopeScale'] as num?)?.toDouble() ?? 0.25,
      jointVelocityScale: _tuple4(json['jointVelocityScale'], 'jointVelocityScale',
          defaultValue: (0.05, 0.05, 0.05, 0.05)),
      actionScale: _tuple4(json['actionScale'], 'actionScale',
          defaultValue: (0.125, 0.25, 0.25, 5.0)),
    );
  }

  static String _reqString(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) throw FormatException('Missing required field: "$key"');
    if (v is! String) {
      throw FormatException('Field "$key" must be a string, got ${v.runtimeType}');
    }
    return v;
  }

  static JointsMatrix _joints16(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) throw FormatException('Missing required field: "$key"');
    if (v is! List) {
      throw FormatException('Field "$key" must be a list, got ${v.runtimeType}');
    }
    if (v.length != 16) {
      throw FormatException('Field "$key" must have 16 elements, got ${v.length}');
    }
    return JointsMatrix.fromList(v.map((e) => (e as num).toDouble()).toList());
  }

  static (double, double, double, double) _tuple4(
    dynamic v,
    String key, {
    required (double, double, double, double) defaultValue,
  }) {
    if (v == null) return defaultValue;
    if (v is! List) {
      throw FormatException('Field "$key" must be a list, got ${v.runtimeType}');
    }
    if (v.length < 4) {
      throw FormatException('Field "$key" must have at least 4 elements, got ${v.length}');
    }
    final list = v.map((e) => (e as num).toDouble()).toList();
    return (list[0], list[1], list[2], list[3]);
  }

  /// 从当前 profile 参数创建对应的 [ObservationBuilder]。
  ObservationBuilder toObservationBuilder() => StandardObservationBuilder(
    standingPose: standingPose,
    imuGyroscopeScale: imuGyroscopeScale,
    jointVelocityScale: jointVelocityScale,
    actionScale: actionScale,
  );

  @override
  String toString() => 'RobotProfile($name, model=$modelPath)';
}

/// 从目录加载所有 profile JSON 文件。
/// 返回 name → RobotProfile 映射。
Future<Map<String, RobotProfile>> loadProfiles(String directory) async {
  final dir = Directory(directory);
  final profiles = <String, RobotProfile>{};
  if (!await dir.exists()) {
    _log.warning('Profile directory not found: $directory');
    return profiles;
  }
  await for (final entity in dir.list()) {
    if (entity is File && entity.path.endsWith('.json')) {
      try {
        final content = await entity.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final profile = RobotProfile.fromJson(json);
        profiles[profile.name] = profile;
        _log.info('Loaded profile: ${profile.name} from ${entity.path}');
      } catch (e, st) {
        _log.warning('Failed to load profile from ${entity.path}', e, st);
      }
    }
  }
  return profiles;
}
