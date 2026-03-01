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
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      modelPath: json['modelPath'] as String,
      standingPose: _joints(json['standingPose']),
      sittingPose: _joints(json['sittingPose']),
      standUpCounts: (json['standUpCounts'] as num?)?.toInt() ?? 150,
      sitDownCounts: (json['sitDownCounts'] as num?)?.toInt() ?? 150,
      inferKp: _joints(json['inferKp']),
      inferKd: _joints(json['inferKd']),
      standUpKp: _joints(json['standUpKp']),
      standUpKd: _joints(json['standUpKd']),
      sitDownKp: _joints(json['sitDownKp']),
      sitDownKd: _joints(json['sitDownKd']),
      imuGyroscopeScale: (json['imuGyroscopeScale'] as num?)?.toDouble() ?? 0.25,
      jointVelocityScale: _tuple4(json['jointVelocityScale']),
      actionScale: _tuple4(json['actionScale']),
    );
  }

  static JointsMatrix _joints(dynamic v) {
    final list = (v as List).map((e) => (e as num).toDouble()).toList();
    return JointsMatrix.fromList(list);
  }

  static (double, double, double, double) _tuple4(dynamic v) {
    if (v == null) return (0.05, 0.05, 0.05, 0.05);
    final list = (v as List).map((e) => (e as num).toDouble()).toList();
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
      } catch (e) {
        _log.warning('Failed to load profile from ${entity.path}: $e');
      }
    }
  }
  return profiles;
}
