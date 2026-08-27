import 'dart:convert';
import 'dart:io';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

final _log = Logger('han_dog.profile.loader');

bool isBodyHeightObservationType(String observationType) =>
    observationType == 'bodyHeight' ||
    observationType == 'singleFrameHeight';

/// 机器人策略配置：一套完整的模型 + 姿态 + 增益 + 缩放参数。
class RobotProfile {
  final String name;
  final String description;
  final String modelPath;
  final String? inputName;
  final JointsMatrix standingPose;
  final JointsMatrix standUpPose;
  final JointsMatrix policyDefaultPose;
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
  final String observationType;
  final double bodyHeightCommand;
  final double minBodyHeightCommand;
  final double maxBodyHeightCommand;
  final double bodyHeightRateLimit;
  final (double, double, double) velocityCommandMin;
  final (double, double, double) velocityCommandMax;

  const RobotProfile({
    required this.name,
    this.description = '',
    required this.modelPath,
    this.inputName,
    required this.standingPose,
    JointsMatrix? standUpPose,
    JointsMatrix? policyDefaultPose,
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
    this.observationType = 'standard',
    this.bodyHeightCommand = 0.35,
    this.minBodyHeightCommand = 0.20,
    this.maxBodyHeightCommand = 0.54,
    this.bodyHeightRateLimit = 0.02,
    this.velocityCommandMin = (-3.0, -3.0, -3.0),
    this.velocityCommandMax = (3.0, 3.0, 3.0),
  }) : standUpPose = standUpPose ?? standingPose,
       policyDefaultPose = policyDefaultPose ?? standingPose;

  factory RobotProfile.fromJson(Map<String, dynamic> json) {
    final inputValue = json['inputName'];
    if (inputValue != null &&
        (inputValue is! String || inputValue.trim().isEmpty)) {
      throw const FormatException(
        'Field "inputName" must be a non-empty string',
      );
    }
    final observationValue = json['observationType'] ?? 'standard';
    if (observationValue is! String) {
      throw FormatException('Field "observationType" must be a string');
    }
    if (observationValue != 'standard' &&
        !isBodyHeightObservationType(observationValue)) {
      throw FormatException('Unknown observationType: $observationValue');
    }

    final bodyHeightCommand = _finiteDouble(json, 'bodyHeightCommand', 0.35);
    final minBodyHeightCommand = _finiteDouble(
      json,
      'minBodyHeightCommand',
      0.20,
    );
    final maxBodyHeightCommand = _finiteDouble(
      json,
      'maxBodyHeightCommand',
      0.54,
    );
    if (minBodyHeightCommand > maxBodyHeightCommand) {
      throw const FormatException(
        'minBodyHeightCommand must be <= maxBodyHeightCommand',
      );
    }
    if (bodyHeightCommand < minBodyHeightCommand ||
        bodyHeightCommand > maxBodyHeightCommand) {
      throw const FormatException(
        'bodyHeightCommand must be within the configured range',
      );
    }
    final bodyHeightRateLimit = _finiteDouble(
      json,
      'bodyHeightRateLimit',
      0.02,
    );
    if (bodyHeightRateLimit <= 0) {
      throw const FormatException('bodyHeightRateLimit must be greater than 0');
    }

    final velocityCommandMin = _tuple3(
      json['velocityCommandMin'],
      'velocityCommandMin',
      defaultValue: (-3.0, -3.0, -3.0),
    );
    final velocityCommandMax = _tuple3(
      json['velocityCommandMax'],
      'velocityCommandMax',
      defaultValue: (3.0, 3.0, 3.0),
    );
    final mins = [
      velocityCommandMin.$1,
      velocityCommandMin.$2,
      velocityCommandMin.$3,
    ];
    final maxs = [
      velocityCommandMax.$1,
      velocityCommandMax.$2,
      velocityCommandMax.$3,
    ];
    for (var i = 0; i < mins.length; i++) {
      if (mins[i] > maxs[i]) {
        throw FormatException(
          'velocityCommandMin must be <= velocityCommandMax at axis $i',
        );
      }
    }

    final standingPose = _joints16(json, 'standingPose');
    final standUpPose = json.containsKey('standUpPose')
        ? _joints16(json, 'standUpPose')
        : standingPose;
    final policyDefaultPose = json.containsKey('policyDefaultPose')
        ? _joints16(json, 'policyDefaultPose')
        : standingPose;

    return RobotProfile(
      name: _reqString(json, 'name'),
      description: json['description'] as String? ?? '',
      modelPath: _reqString(json, 'modelPath'),
      inputName: inputValue as String?,
      standingPose: standingPose,
      standUpPose: standUpPose,
      policyDefaultPose: policyDefaultPose,
      sittingPose: _joints16(json, 'sittingPose'),
      standUpCounts: (json['standUpCounts'] as num?)?.toInt() ?? 150,
      sitDownCounts: (json['sitDownCounts'] as num?)?.toInt() ?? 150,
      inferKp: _joints16(json, 'inferKp'),
      inferKd: _joints16(json, 'inferKd'),
      standUpKp: _joints16(json, 'standUpKp'),
      standUpKd: _joints16(json, 'standUpKd'),
      sitDownKp: _joints16(json, 'sitDownKp'),
      sitDownKd: _joints16(json, 'sitDownKd'),
      imuGyroscopeScale: _finiteDouble(json, 'imuGyroscopeScale', 0.25),
      jointVelocityScale: _tuple4(
        json['jointVelocityScale'],
        'jointVelocityScale',
        defaultValue: (0.05, 0.05, 0.05, 0.05),
      ),
      actionScale: _tuple4(
        json['actionScale'],
        'actionScale',
        defaultValue: (0.125, 0.25, 0.25, 5.0),
      ),
      observationType: observationValue,
      bodyHeightCommand: bodyHeightCommand,
      minBodyHeightCommand: minBodyHeightCommand,
      maxBodyHeightCommand: maxBodyHeightCommand,
      bodyHeightRateLimit: bodyHeightRateLimit,
      velocityCommandMin: velocityCommandMin,
      velocityCommandMax: velocityCommandMax,
    );
  }

  static String _reqString(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) throw FormatException('Missing required field: "$key"');
    if (v is! String) {
      throw FormatException(
        'Field "$key" must be a string, got ${v.runtimeType}',
      );
    }
    return v;
  }

  static double _finiteDouble(
    Map<String, dynamic> json,
    String key,
    double defaultValue,
  ) {
    final v = json[key];
    if (v == null) return defaultValue;
    if (v is! num) {
      throw FormatException(
        'Field "$key" must be a number, got ${v.runtimeType}',
      );
    }
    final d = v.toDouble();
    if (!d.isFinite) {
      throw FormatException('Field "$key" must be finite, got $d');
    }
    return d;
  }

  static JointsMatrix _joints16(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) throw FormatException('Missing required field: "$key"');
    if (v is! List) {
      throw FormatException(
        'Field "$key" must be a list, got ${v.runtimeType}',
      );
    }
    if (v.length != 16) {
      throw FormatException(
        'Field "$key" must have 16 elements, got ${v.length}',
      );
    }
    final doubles = <double>[];
    for (int i = 0; i < v.length; i++) {
      final e = v[i];
      if (e is! num) {
        throw FormatException(
          'Field "$key" element at index $i must be a number, got ${e.runtimeType}: $e',
        );
      }
      final d = e.toDouble();
      if (!d.isFinite) {
        throw FormatException(
          'Field "$key" contains non-finite value at index $i: $d',
        );
      }
      doubles.add(d);
    }
    return JointsMatrix.fromList(doubles);
  }

  static (double, double, double) _tuple3(
    dynamic value,
    String key, {
    required (double, double, double) defaultValue,
  }) {
    if (value == null) return defaultValue;
    if (value is! List) {
      throw FormatException(
        'Field "$key" must be a list, got ${value.runtimeType}',
      );
    }
    if (value.length != 3) {
      throw FormatException(
        'Field "$key" must have 3 elements, got ${value.length}',
      );
    }
    final values = <double>[];
    for (var i = 0; i < value.length; i++) {
      final element = value[i];
      if (element is! num) {
        throw FormatException(
          'Field "$key" element at index $i must be a number',
        );
      }
      final number = element.toDouble();
      if (!number.isFinite) {
        throw FormatException('Field "$key" contains a non-finite value');
      }
      values.add(number);
    }
    return (values[0], values[1], values[2]);
  }

  static (double, double, double, double) _tuple4(
    dynamic v,
    String key, {
    required (double, double, double, double) defaultValue,
  }) {
    if (v == null) return defaultValue;
    if (v is! List) {
      throw FormatException(
        'Field "$key" must be a list, got ${v.runtimeType}',
      );
    }
    if (v.length < 4) {
      throw FormatException(
        'Field "$key" must have at least 4 elements, got ${v.length}',
      );
    }
    final list = <double>[];
    for (int i = 0; i < v.length; i++) {
      final e = v[i];
      if (e is! num) {
        throw FormatException(
          'Field "$key" element at index $i must be a number, got ${e.runtimeType}: $e',
        );
      }
      final d = e.toDouble();
      if (i < 4 && !d.isFinite) {
        throw FormatException(
          'Field "$key" contains non-finite value at index $i: $d',
        );
      }
      list.add(d);
    }
    return (list[0], list[1], list[2], list[3]);
  }

  /// 从当前 profile 参数创建对应的 [ObservationBuilder]。
  ObservationBuilder toObservationBuilder() {
    return switch (observationType) {
      'standard' => StandardObservationBuilder(
        standingPose: policyDefaultPose,
        imuGyroscopeScale: imuGyroscopeScale,
        jointVelocityScale: jointVelocityScale,
        actionScale: actionScale,
      ),
      'bodyHeight' => BodyHeightObservationBuilder(
        standingPose: policyDefaultPose,
        imuGyroscopeScale: imuGyroscopeScale,
        jointVelocityScale: jointVelocityScale,
        actionScale: actionScale,
      ),
      'singleFrameHeight' => SingleFrameHeightObservationBuilder(
        standingPose: policyDefaultPose,
        imuGyroscopeScale: imuGyroscopeScale,
        jointVelocityScale: jointVelocityScale,
        actionScale: actionScale,
      ),
      _ => throw StateError('Unsupported observationType: $observationType'),
    };
  }

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
