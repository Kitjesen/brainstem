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

  bool _switching = false;

  ProfileManager({
    required Map<String, RobotProfile> profiles,
    required this.brain,
    this.gains,
    this.controlDog,
    required String initial,
  })  : _profiles = Map.of(profiles),
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
  ///
  /// 若切换失败（如模型加载错误），自动回滚增益到切换前的策略。
  /// 若上一次切换尚未完成，抛出 [StateError]。
  Future<void> switchTo(String name) async {
    if (_switching) {
      throw StateError('Profile switch already in progress (current: $_current)');
    }
    if (name == _current) {
      _log.fine('Already on profile: $name');
      return;
    }
    final p = _profiles[name];
    if (p == null) {
      throw ArgumentError('Unknown profile: $name '
          '(available: ${_profiles.keys.join(", ")})');
    }

    final prevName = _current;
    final prevProfile = _profiles[prevName]!;
    _log.info('Switching profile: $prevName → $name');

    _switching = true;
    try {
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
    } catch (e, st) {
      _log.warning(
          'Profile switch failed ($prevName → $name): $e; attempting gain rollback',
          e, st);
      try {
        _switchGains(prevProfile);
        _log.info('Gain rollback to "$prevName" succeeded');
      } catch (rollbackE, rollbackSt) {
        // Rollback failed: log as SEVERE and continue with rethrow of original.
        // _current is NOT updated, so the name stays consistent, but gains
        // may be in an indeterminate state — operator must intervene.
        _log.severe(
          'CRITICAL: gain rollback to "$prevName" also failed after '
          'profile switch error — robot gains may be indeterminate. '
          'Original error was: $e',
          rollbackE,
          rollbackSt,
        );
      }
      rethrow;
    } finally {
      _switching = false;
    }
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

  /// 热加载：重新扫描 [profileDir]，添加新策略、更新非当前策略。
  ///
  /// 当前正在运行的策略不会被替换（以免中断运行中的推理）。
  /// 切换进行中时跳过本次扫描，避免数据竞争。
  Future<void> reload(String profileDir) async {
    if (_switching) {
      _log.fine('Profile reload skipped: switch in progress');
      return;
    }
    final fresh = await loadProfiles(profileDir);
    int added = 0;
    int updated = 0;
    for (final entry in fresh.entries) {
      if (entry.key == _current) continue; // 不替换运行中的策略
      if (_profiles.containsKey(entry.key)) {
        _profiles[entry.key] = entry.value;
        updated++;
      } else {
        _profiles[entry.key] = entry.value;
        added++;
      }
    }
    if (added > 0 || updated > 0) {
      _log.info('Profile hot-reload: +$added 新, ~$updated 更新 (current=$_current)');
    }
  }
}
