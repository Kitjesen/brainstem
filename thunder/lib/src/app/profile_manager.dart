import 'dart:async';

import 'package:thunder_brain/thunder_brain.dart';
import 'package:logging/logging.dart';

import '../real_control_dog.dart';
import '../server/gain_manager.dart';
import 'robot_profile.dart';
import 'operator_mode_slots.dart';
import 'voice_announcer.dart';

final _log = Logger('thunder.profile.manager');

// TODO(phase2): Evaluate moving ProfileManager to a shared library —
// currently in thunder but also needed by thunder_brain's server.dart.

/// 策略切换编排器：汇集 Brain / GainManager / RealControlDog 的切换逻辑。
class ProfileManager {
  final OperatorModeSlots? operatorSlots;
  final Map<String, RobotProfile> _profiles;
  final Brain brain;
  final GainManager? gains;
  final RealControlDog? controlDog;
  final void Function(String reason)? onFault;
  final VoiceAnnouncer? voice;
  String _current;

  bool _switching = false;
  bool _hasFault = false;

  bool get hasFault => _hasFault;

  ProfileManager({
    required Map<String, RobotProfile> profiles,
    required this.brain,
    this.gains,
    this.controlDog,
    this.onFault,
    this.operatorSlots,
    this.voice,
    required String initial,
  }) : _profiles = Map.of(profiles),
       _current = initial;

  /// 当前策略名称。
  String get currentName => _current;

  /// 当前策略说明。
  String get currentDescription => _profiles[_current]?.description ?? '';

  /// 所有可用策略名称。
  List<String> get names => _profiles.keys.toList();

  /// 所有策略说明（与 names 按索引对应）。
  List<String> get descriptions =>
      _profiles.values.map((p) => p.description).toList();

  List<String> get operatorNames => operatorSlots?.profileNames ?? const [];
  List<String> get operatorDescriptions => [
    for (final name in operatorNames)
      '${name == operatorSlots!.flat
          ? "flat"
          : name == operatorSlots!.stairs
          ? "stairs"
          : "high_platform"}: ${_profiles[name]?.description ?? ""}',
  ];

  /// Radio and gRPC share the same frozen, preloaded operator profiles.
  Future<void> switchOperatorProfile(
    String slotOrName, {
    required bool Function() canCommit,
  }) async {
    final slots = operatorSlots;
    if (slots == null) throw StateError('Operator slots are not configured');
    final target = operatorNames.contains(slotOrName)
        ? slotOrName
        : switch (slotOrName) {
            'flat' => slots.flat,
            'stairs' => slots.stairs,
            'high_platform' => slots.highPlatform,
            _ => null,
          };
    if (target == null) {
      throw ArgumentError('Unknown or unassigned operator slot: $slotOrName');
    }
    if (!operatorNames.contains(_current)) {
      throw StateError('Current profile is outside operator slots');
    }
    slots.validateProfiles(_profiles);
    if (!canCommit()) throw StateError('Operator switch no longer permitted');
    await switchTo(target, canCommit: canCommit, usePrepared: true);
  }

  /// 切换到指定策略。机器人必须在 Grounded 状态（由调用方保证）。
  ///
  /// 若切换失败（如模型加载错误），自动回滚增益和指令包络。
  /// 若上一次切换尚未完成，抛出 [StateError]。
  Future<void> switchTo(
    String name, {
    bool Function()? canCommit,
    bool usePrepared = false,
  }) async {
    if (_hasFault) throw StateError('Profile manager has an unresolved fault');
    if (_switching) {
      throw StateError(
        'Profile switch already in progress (current: $_current)',
      );
    }
    if (name == _current) {
      _log.fine('Already on profile: $name');
      return;
    }
    final p = _profiles[name];
    if (p == null) {
      throw ArgumentError(
        'Unknown profile: $name '
        '(available: ${_profiles.keys.join(", ")})',
      );
    }

    final prevName = _current;
    final prevProfile = _profiles[prevName]!;
    final prevGestureLibrary = brain.gestureLibrary;
    var brainChanged = false;
    _log.info('Switching profile: $prevName → $name');

    _switching = true;
    try {
      // 1. Brain：替换行为 + 加载模型
      await brain.switchProfile(
        observationBuilder: p.toObservationBuilder(),
        forceZeroWheelOnStop: p.forceZeroWheelOnStop,
        standingPose: p.standingPose,
        sittingPose: p.sittingPose,
        modelPath: p.modelPath,
        standUpCounts: p.standUpCounts,
        sitDownCounts: p.sitDownCounts,
        canCommit: canCommit,
        preparedProfile: usePrepared ? name : null,
      );
      brainChanged = true;
      if (canCommit != null && !canCommit()) {
        throw StateError(
          'Profile switch cancelled before control parameters commit',
        );
      }

      // 2. GestureLibrary（保存旧值以便回滚）
      brain.gestureLibrary = GestureLibrary(standingPose: p.standingPose)
        ..registerDefaults();

      // 3. GainManager + 实机命令包络
      try {
        _switchControlProfile(p);
      } catch (_) {
        // 增益切换失败：回滚 GestureLibrary 到切换前的状态
        brain.gestureLibrary = prevGestureLibrary;
        rethrow;
      }

      _current = name;
      _log.info('Switched to profile: $name (model=${p.modelPath})');
    } catch (e, st) {
      _log.warning(
        'Profile switch failed ($prevName → $name): $e; attempting rollback',
        e,
        st,
      );
      try {
        if (brainChanged) {
          await brain.switchProfile(
            observationBuilder: prevProfile.toObservationBuilder(),
            forceZeroWheelOnStop: prevProfile.forceZeroWheelOnStop,
            standingPose: prevProfile.standingPose,
            sittingPose: prevProfile.sittingPose,
            modelPath: prevProfile.modelPath,
            standUpCounts: prevProfile.standUpCounts,
            sitDownCounts: prevProfile.sitDownCounts,
            preparedProfile: usePrepared ? prevName : null,
          );
        }
        _switchControlProfile(prevProfile);
        brain.gestureLibrary = prevGestureLibrary;
        _log.info('Rollback to "$prevName" succeeded');
      } catch (rollbackE, rollbackSt) {
        // Rollback failed: gains and gestureLibrary may be in an
        // indeterminate state — trigger fault to force safe shutdown.
        _log.severe(
          'CRITICAL: rollback to "$prevName" also failed after '
          'profile switch error — triggering fault. '
          'Original error was: $e',
          rollbackE,
          rollbackSt,
        );
        _hasFault = true;
        onFault?.call(
          'Profile switch + rollback both failed: '
          'original=$e, rollback=$rollbackE',
        );
      }
      rethrow;
    } finally {
      _switching = false;
    }
    // Speech is outside the transaction: output failure must never roll it back.
    unawaited(_announceSwitched(name));
  }

  Future<void> _announceSwitched(String name) async {
    final output = voice;
    if (output == null) return;
    final (asset, text) = name == operatorSlots?.flat
        ? ('mode_flat.wav', '已切换至平地模式。')
        : name == operatorSlots?.stairs
        ? ('mode_stairs.wav', '已切换至楼梯模式。')
        : ('profile_changed.wav', '策略切换成功。');
    try {
      await output.announce(
        VoiceAnnouncement(
          key: 'profile_switched',
          text: text,
          audioAsset: asset,
        ),
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Profile committed but voice failed: $name',
        error,
        stackTrace,
      );
    }
  }

  void _switchControlProfile(RobotProfile p) {
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
    controlDog?.switchCommandProfile(
      commandVxMax: p.commandVxMax,
      commandVyMax: p.commandVyMax,
      commandYawMax: p.commandYawMax,
      forwardMinCommand: p.forwardMinCommand,
      lateralMinCommand: p.lateralMinCommand,
      yawMinCommand: p.yawMinCommand,
    );
  }

  /// YUNZHUO R2 切换：在已有策略间循环。
  Future<void> toggle() async {
    final slots = operatorSlots;
    if (slots == null) throw StateError('R2 operator modes are not configured');
    if (controlDog == null || !controlDog!.canSwitchProfile) {
      throw StateError(
        'R2 requires grounded or L1 completed standing with centered sticks',
      );
    }
    if (!slots.profileNames.contains(_current)) {
      throw StateError('Both accepted R2 slots must exist; current=$_current');
    }
    slots.validateProfiles(_profiles);
    final names = slots.profileNames;
    final next = names[(names.indexOf(_current) + 1) % names.length];
    await switchOperatorProfile(
      next,
      canCommit: () => controlDog!.canSwitchProfile,
    );
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
    if (_switching) return;
    int added = 0;
    int updated = 0;
    // 添加或更新磁盘上存在的策略
    for (final entry in fresh.entries) {
      if (operatorSlots?.profileNames.contains(entry.key) ?? false) {
        continue; // Accepted slots change at restart only.
      }
      if (entry.key == _current) continue; // 不替换运行中的策略
      if (_profiles.containsKey(entry.key)) {
        _profiles[entry.key] = entry.value;
        updated++;
      } else {
        _profiles[entry.key] = entry.value;
        added++;
      }
    }
    // 移除磁盘上已删除的策略（当前运行的策略不受影响）
    final toRemove = _profiles.keys
        .where(
          (k) =>
              k != _current &&
              !fresh.containsKey(k) &&
              !(operatorSlots?.profileNames.contains(k) ?? false),
        )
        .toList();
    for (final k in toRemove) {
      _profiles.remove(k);
    }
    final removed = toRemove.length;
    if (added > 0 || updated > 0 || removed > 0) {
      _log.info(
        'Profile hot-reload: +$added 新, ~$updated 更新, -$removed 移除 (current=$_current)',
      );
    }
  }
}
