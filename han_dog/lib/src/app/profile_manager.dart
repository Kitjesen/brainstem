import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';

import '../real_control_dog.dart';
import '../server/gain_manager.dart';
import 'robot_profile.dart';

final _log = Logger('han_dog.profile');

/// 策略切换编排器：汇集 Brain / GainManager / RealControlDog 的切换逻辑。
class ProfileManager {
  final Map<String, RobotProfile> _profiles;
  final Brain brain;
  final GainManager? gains;
  final RealControlDog? controlDog;
  String _current;

  ProfileManager({
    required Map<String, RobotProfile> profiles,
    required this.brain,
    this.gains,
    this.controlDog,
    required String initial,
  })  : _profiles = Map.unmodifiable(profiles),
        _current = initial;

  /// 当前策略名称。
  String get currentName => _current;

  /// 当前策略说明。
  String get currentDescription => _profiles[_current]?.description ?? '';

  /// 所有可用策略名称。
  List<String> get names => _profiles.keys.toList();

  /// 所有策略说明（与 names 按索引对应）。
  List<String> get descriptions => _profiles.values.map((p) => p.description).toList();

  /// 切换到指定策略。机器人必须在 Grounded 状态（由调用方保证）。
  Future<void> switchTo(String name) async {
    if (name == _current) {
      _log.fine('Already on profile: $name');
      return;
    }
    final p = _profiles[name];
    if (p == null) {
      throw ArgumentError('Unknown profile: $name '
          '(available: ${_profiles.keys.join(", ")})');
    }

    _log.info('Switching profile: $_current → $name');

    // 1. Brain：替换行为 + 加载模型
    await brain.switchProfile(
      observationBuilder: p.toObservationBuilder(),
      standingPose: p.standingPose,
      sittingPose: p.sittingPose,
      modelPath: p.modelPath,
      standUpCounts: p.standUpCounts,
      sitDownCounts: p.sitDownCounts,
    );

    // 2. GestureLibrary
    brain.gestureLibrary = GestureLibrary(standingPose: p.standingPose)
      ..registerDefaults();

    // 3. GainManager（gRPC 服务用）
    _switchGains(p);

    _current = name;
    _log.info('Switched to profile: $name (model=${p.modelPath})');
  }

  void _switchGains(RobotProfile p) {
    gains?.switchGains(
      inferKp: p.inferKp,
      inferKd: p.inferKd,
      standUpKp: p.standUpKp,
      standUpKd: p.standUpKd,
      sitDownKp: p.sitDownKp,
      sitDownKd: p.sitDownKd,
    );
    controlDog?.switchGains(
      inferKp: p.inferKp,
      inferKd: p.inferKd,
      standUpKp: p.standUpKp,
      standUpKd: p.standUpKd,
      sitDownKp: p.sitDownKp,
      sitDownKd: p.sitDownKd,
    );
  }

  /// YUNZHUO R2 切换：在已有策略间循环。
  Future<void> toggle() async {
    final keys = names;
    if (keys.length <= 1) return;
    final idx = keys.indexOf(_current);
    final next = keys[(idx + 1) % keys.length];
    await switchTo(next);
  }
}
