import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

final _log = Logger('thunder_brain.gesture');

/// Clips that may appear in the onboard catalog, but must never be used
/// in place of the official StandUp behaviour.
const Set<String> libraryStandClipNames = {'wake_stand', 'stand_up'};

/// Default on-dog paths for the Thunder V4 sparse keyframe library.
/// Override with `THUNDER_GESTURE_CATALOG` and `THUNDER_GESTURE_LIBRARY`.
abstract final class GestureLibraryPaths {
  static const String catalog =
      '/home/sunrise/gesture-library/gestures/index.json';
  static const String bundle =
      '/home/sunrise/gesture-library/gestures/library.json';

  static String catalogPath([Map<String, String>? environment]) {
    final value =
        (environment ?? Platform.environment)['THUNDER_GESTURE_CATALOG'];
    if (value != null && value.isNotEmpty) return value;
    return catalog;
  }

  static String bundlePath([Map<String, String>? environment]) {
    final value =
        (environment ?? Platform.environment)['THUNDER_GESTURE_LIBRARY'];
    if (value != null && value.isNotEmpty) return value;
    return bundle;
  }
}

/// Pose a clip expects at the start, or leaves behind at the end.
enum GesturePose { standing, sitting, lying }

/// 关键帧：一个目标姿态 + 到达该姿态的插值帧数。
class Keyframe {
  final JointsMatrix targetPose;

  /// 从上一姿态插值到 [targetPose] 所需的控制拍数。一拍 20 ms。
  ///
  /// * `0`：下一拍直接落到目标（一拍，t = 1）。
  /// * `N > 0`：线性插值 N 拍，t = 1/N, 2/N, …, 1。
  ///
  /// 片段开头不再多停一拍。动作库按这个规则计时，不要把那 20 ms 编进去。
  final int counts;

  const Keyframe({required this.targetPose, required this.counts});

  Map<String, dynamic> toJson() => {
    'targetPose': targetPose.values,
    'counts': counts,
  };

  factory Keyframe.fromJson(Map<String, dynamic> json) => Keyframe(
    targetPose: JointsMatrix.fromList(
      (json['targetPose'] as List).map((v) => (v as num).toDouble()).toList(),
    ),
    counts: (json['counts'] as num).toInt(),
  );
}

GesturePose _poseOrDefault(Object? raw, GesturePose fallback) {
  return switch (raw) {
    null => fallback,
    'standing' => GesturePose.standing,
    'sitting' => GesturePose.sitting,
    'lying' => GesturePose.lying,
    _ => throw FormatException('Unknown pose: $raw'),
  };
}

GesturePose _requiredPose(Object? raw, String field) {
  return switch (raw) {
    'standing' => GesturePose.standing,
    'sitting' => GesturePose.sitting,
    'lying' => GesturePose.lying,
    _ => throw FormatException('Unknown $field: $raw'),
  };
}

int? _optionalDurationMs(Map<String, dynamic> json) {
  final ms = json['duration_ms'];
  if (ms is num) return ms.round();
  final seconds = json['duration_s'];
  if (seconds is num) return (seconds * 1000).round();
  return null;
}

bool? _optionalKeepsWheels(Map<String, dynamic> json) {
  final playback = json['playback'];
  if (playback == 'joint_lerp_keep_wheels') return true;
  if (playback == 'joint_lerp') return false;
  final usesWheels = json['uses_wheels'];
  if (usesWheels is bool) return usesWheels;
  return null;
}

String? _catalogDescription(Map<String, dynamic> json) {
  final description = json['description'];
  if (description is String && description.isNotEmpty) return description;
  final titleZh = json['title_zh'];
  if (titleZh is String && titleZh.isNotEmpty) return titleZh;
  final title = json['title'];
  if (title is String && title.isNotEmpty) return title;
  return null;
}

bool _reportedMissingOnboardLibrary = false;

/// 动作定义：一组关键帧序列。
class GestureDefinition {
  static const double wheelEpsilon = 0.01;

  final String name;
  final String? description;
  final List<Keyframe> keyframes;
  final GesturePose startPose;
  final GesturePose endPose;

  /// Catalog duration in milliseconds. Null means [playbackDurationMs]
  /// is derived from the keyframe tick count.
  final int? durationMs;

  /// When true, playback keeps wheel targets. `discardFoot()` would zero them.
  final bool keepsWheels;

  GestureDefinition({
    required this.name,
    this.description,
    required this.keyframes,
    this.startPose = GesturePose.standing,
    this.endPose = GesturePose.standing,
    this.durationMs,
    bool? keepsWheels,
  }) : keepsWheels = keepsWheels ?? wheelsMove(keyframes) {
    if (keyframes.isEmpty) {
      throw ArgumentError.value(
        keyframes,
        'keyframes',
        'GestureDefinition "$name" must have at least one keyframe',
      );
    }
  }

  /// True when any wheel target exceeds the sparsify noise floor.
  static bool wheelsMove(List<Keyframe> keyframes) {
    for (final frame in keyframes) {
      final values = frame.targetPose.values;
      for (var i = 12; i < values.length && i < 16; i++) {
        if (values[i].abs() > wheelEpsilon) return true;
      }
    }
    return false;
  }

  int get tickCount {
    var ticks = 0;
    for (final frame in keyframes) {
      ticks += frame.counts <= 0 ? 1 : frame.counts;
    }
    return ticks;
  }

  /// Catalog duration when present, otherwise `tickCount * 20`.
  int get playbackDurationMs => durationMs ?? tickCount * 20;

  GestureDefinition withCatalog({
    String? description,
    int? durationMs,
    required GesturePose startPose,
    required GesturePose endPose,
    required bool keepsWheels,
  }) {
    return GestureDefinition(
      name: name,
      description: description ?? this.description,
      keyframes: keyframes,
      startPose: startPose,
      endPose: endPose,
      durationMs: durationMs ?? this.durationMs,
      keepsWheels: keepsWheels,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (startPose != GesturePose.standing) 'start_pose': startPose.name,
    if (endPose != GesturePose.standing) 'end_pose': endPose.name,
    if (durationMs != null) 'duration_ms': durationMs,
    if (keepsWheels) 'playback': 'joint_lerp_keep_wheels',
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };

  factory GestureDefinition.fromJson(Map<String, dynamic> json) {
    final keyframes = (json['keyframes'] as List<dynamic>)
        .map((k) => Keyframe.fromJson(k as Map<String, dynamic>))
        .toList();
    return GestureDefinition(
      name: json['name'] as String,
      description: json['description'] as String?,
      keyframes: keyframes,
      startPose: _poseOrDefault(json['start_pose'], GesturePose.standing),
      endPose: _poseOrDefault(json['end_pose'], GesturePose.standing),
      durationMs: _optionalDurationMs(json),
      keepsWheels: _optionalKeepsWheels(json) ?? wheelsMove(keyframes),
    );
  }
}

/// 动作库：存储和管理命名动作定义。
class GestureLibrary {
  final Map<String, GestureDefinition> _gestures = {};
  final JointsMatrix standingPose;

  /// Catalog order. Null until [applyIndex] runs.
  List<String>? _catalogNames;

  GestureLibrary({required this.standingPose});

  bool get hasOnboardCatalog => _catalogNames != null;

  /// Clips exposed by ListGestures.
  ///
  /// A loaded onboard catalog replaces this list: built-in bow/nod/wiggle
  /// stay registered for direct playback, but they are not official posture
  /// commands and are not added beside the catalog. StandUp and SitDown are
  /// never entries. `wake_stand` and `stand_up` are listed only when the
  /// catalog contains them, and they are ordinary clips.
  List<GestureDefinition> get listedGestures {
    final catalog = _catalogNames;
    if (catalog == null) {
      return [for (final name in names) get(name)!];
    }
    return [for (final name in catalog) get(name)!];
  }

  void register(GestureDefinition definition) {
    if (_gestures.containsKey(definition.name)) {
      _log.warning('Overwriting existing gesture: "${definition.name}"');
    }
    _gestures[definition.name] = definition;
    _log.fine('Registered gesture: ${definition.name}');
  }

  GestureDefinition? get(String name) => _gestures[name];

  List<String> get names => _gestures.keys.toList();

  bool contains(String name) => _gestures.containsKey(name);

  /// 从 JSON 字符串批量加载动作定义。
  void loadFromJson(String jsonString) {
    try {
      final list = jsonDecode(jsonString) as List<dynamic>;
      for (final item in list) {
        register(GestureDefinition.fromJson(item as Map<String, dynamic>));
      }
    } catch (e, st) {
      _log.warning('loadFromJson failed', e, st);
      rethrow;
    }
  }

  /// Attach ListGestures metadata from `gestures/index.json`.
  ///
  /// Entries without a loaded clip are skipped. Official StandUp / SitDown
  /// are not inserted. Catalog order is preserved.
  void applyIndex(String indexJson) {
    final decoded = jsonDecode(indexJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('gesture index must be a JSON object');
    }
    final gestures = decoded['gestures'];
    if (gestures is! List<dynamic>) {
      throw const FormatException('gesture index is missing "gestures"');
    }
    final listed = <String>[];
    for (final item in gestures) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('gesture catalog entry must be an object');
      }
      final name = item['name'];
      if (name is! String || name.isEmpty) {
        throw const FormatException('gesture catalog entry is missing name');
      }
      final existing = _gestures[name];
      if (existing == null) {
        _log.warning('Catalog gesture "$name" is not in the loaded library');
        continue;
      }
      final keeps = _optionalKeepsWheels(item);
      _gestures[name] = existing.withCatalog(
        description: _catalogDescription(item),
        durationMs: _optionalDurationMs(item),
        startPose: _requiredPose(item['start_pose'], 'start_pose'),
        endPose: _requiredPose(item['end_pose'], 'end_pose'),
        keepsWheels: keeps ?? existing.keepsWheels,
      );
      listed.add(name);
    }
    _catalogNames = listed;
  }

  /// Load the on-dog bundle and catalog. Missing files leave the built-in
  /// clips in place and do not throw, so locomotion can still boot.
  void tryLoadOnboard({
    String? catalogPath,
    String? libraryPath,
    Map<String, String>? environment,
  }) {
    final catalog = catalogPath ?? GestureLibraryPaths.catalogPath(environment);
    final bundle = libraryPath ?? GestureLibraryPaths.bundlePath(environment);
    final catalogFile = File(catalog);
    final bundleFile = File(bundle);
    if (!catalogFile.existsSync() || !bundleFile.existsSync()) {
      if (!_reportedMissingOnboardLibrary) {
        _reportedMissingOnboardLibrary = true;
        _log.warning(
          'Onboard gesture library not found '
          '(catalog=$catalog, bundle=$bundle); ListGestures will use '
          'built-in clips only',
        );
      }
      return;
    }
    final previous = Map<String, GestureDefinition>.of(_gestures);
    final previousCatalog = _catalogNames;
    try {
      final libraryText = bundleFile.readAsStringSync();
      final indexText = catalogFile.readAsStringSync();
      loadFromJson(libraryText);
      applyIndex(indexText);
      _log.info(
        'Loaded ${listedGestures.length} onboard gestures from $bundle',
      );
    } catch (e, st) {
      _gestures
        ..clear()
        ..addAll(previous);
      _catalogNames = previousCatalog;
      _log.severe('Failed to load onboard gesture library', e, st);
    }
  }

  /// 导出所有动作为 JSON 字符串。
  String toJson() =>
      jsonEncode(_gestures.values.map((g) => g.toJson()).toList());

  /// 注册内置预定义动作。
  void registerDefaults() {
    register(_bow());
    register(_nod());
    register(_wiggle());
    register(_stretch());
    register(_dance());
    _log.info('Registered ${_gestures.length} default gestures');
  }

  // ── 预定义动作 ──────────────────────────────────────────────

  /// 在 standingPose 基础上按关节偏移构造新姿态。
  /// [offsets] 长度 12：FR(hip,thigh,calf), FL, RR, RL。
  JointsMatrix _offset(List<double> offsets) {
    final v = standingPose.values;
    return JointsMatrix(
      v[0] + offsets[0],
      v[1] + offsets[1],
      v[2] + offsets[2],
      v[3] + offsets[3],
      v[4] + offsets[4],
      v[5] + offsets[5],
      v[6] + offsets[6],
      v[7] + offsets[7],
      v[8] + offsets[8],
      v[9] + offsets[9],
      v[10] + offsets[10],
      v[11] + offsets[11],
      0,
      0,
      0,
      0,
    );
  }

  /// 鞠躬 / 拜年：预备上抬 → 前倾鞠躬 → 保持 → 缓缓起身。
  GestureDefinition _bow() {
    // dart format off
    final antiPose = _offset([
      0, 0.08,-0.12,   0,-0.08, 0.12,   // 前腿微伸（身体上抬）
      0,-0.04, 0.06,   0, 0.04,-0.06,   // 后腿微弯
    ]);
    final bowPose = _offset([
      0,-0.5,  0.8,    0, 0.5, -0.8,    // 前腿深弯
      0, 0.2, -0.35,   0,-0.2,  0.35,   // 后腿略伸
    ]);
    // dart format on
    return GestureDefinition(
      name: 'bow',
      description: '鞠躬 / 拜年',
      keyframes: [
        Keyframe(targetPose: antiPose, counts: 15), // 预备上抬
        Keyframe(targetPose: bowPose, counts: 55), // 鞠躬
        Keyframe(targetPose: bowPose, counts: 50), // 保持
        Keyframe(targetPose: standingPose, counts: 60), // 起身
      ],
    );
  }

  /// 点头：三次递减点头（深 → 中 → 浅），带过冲回弹。
  GestureDefinition _nod() {
    // dart format off
    final nodDeep = _offset([
      0,-0.25, 0.38,   0, 0.25,-0.38,   // 前腿深弯
      0,-0.12, 0.18,   0, 0.12,-0.18,   // 后腿微抬
    ]);
    final nodOvershoot = _offset([
      0, 0.06,-0.09,   0,-0.06, 0.09,   // 前腿微伸（过冲）
      0, 0.03,-0.05,   0,-0.03, 0.05,
    ]);
    final nodLight = _offset([
      0,-0.15, 0.22,   0, 0.15,-0.22,   // 较浅点头
      0,-0.08, 0.12,   0, 0.08,-0.12,
    ]);
    final nodTiny = _offset([
      0,-0.08, 0.12,   0, 0.08,-0.12,   // 微点头收尾
      0,-0.04, 0.06,   0, 0.04,-0.06,
    ]);
    // dart format on
    return GestureDefinition(
      name: 'nod',
      description: '点头',
      keyframes: [
        Keyframe(targetPose: nodDeep, counts: 20), // 第一次深点头
        Keyframe(targetPose: nodOvershoot, counts: 15), // 过冲回弹
        Keyframe(targetPose: nodLight, counts: 18), // 第二次浅点头
        Keyframe(targetPose: standingPose, counts: 12), // 回位
        Keyframe(targetPose: nodTiny, counts: 10), // 第三次微点头
        Keyframe(targetPose: standingPose, counts: 12), // 最终回位
      ],
    );
  }

  /// 扭动：振幅渐强渐弱的左右摇摆，带大腿联动。
  GestureDefinition _wiggle() {
    // 振幅包络：小 → 中 → 大 → 中 → 小
    // 倾斜时大腿微动（secondary action —— 身体自然跟随）
    // dart format off
    final smallL = _offset([-0.08, 0.02,0, -0.08, 0.02,0, -0.08, 0.02,0, -0.08, 0.02,0]);
    final smallR = _offset([ 0.08,-0.02,0,  0.08,-0.02,0,  0.08,-0.02,0,  0.08,-0.02,0]);
    final medL   = _offset([-0.15, 0.04,0, -0.15, 0.04,0, -0.15, 0.04,0, -0.15, 0.04,0]);
    final medR   = _offset([ 0.15,-0.04,0,  0.15,-0.04,0,  0.15,-0.04,0,  0.15,-0.04,0]);
    final fullL  = _offset([-0.22, 0.06,0, -0.22, 0.06,0, -0.22, 0.06,0, -0.22, 0.06,0]);
    final fullR  = _offset([ 0.22,-0.06,0,  0.22,-0.06,0,  0.22,-0.06,0,  0.22,-0.06,0]);
    // dart format on
    return GestureDefinition(
      name: 'wiggle',
      description: '左右扭动',
      keyframes: [
        Keyframe(targetPose: smallL, counts: 12), // 小左
        Keyframe(targetPose: smallR, counts: 12), // 小右
        Keyframe(targetPose: medL, counts: 15), // 中左
        Keyframe(targetPose: medR, counts: 15), // 中右
        Keyframe(targetPose: fullL, counts: 18), // 大左
        Keyframe(targetPose: fullR, counts: 18), // 大右
        Keyframe(targetPose: medL, counts: 15), // 中左
        Keyframe(targetPose: smallR, counts: 12), // 小右
        Keyframe(targetPose: standingPose, counts: 10), // 回位
      ],
    );
  }

  /// 伸展：微蹲蓄力 → 前伸保持 → 后伸保持 → 缓缓回位。
  GestureDefinition _stretch() {
    // dart format off
    final crouchPose = _offset([
      0,-0.1,  0.15,   0, 0.1, -0.15,   // 全身微蹲（anticipation）
      0, 0.1, -0.15,   0,-0.1,  0.15,
    ]);
    final frontStretch = _offset([
      0, 0.35,-0.55,   0,-0.35, 0.55,   // 前腿伸展
      0,-0.25, 0.4,    0, 0.25,-0.4,    // 后腿蹲下
    ]);
    final rearAnti = _offset([
      0, 0.06,-0.09,   0,-0.06, 0.09,   // 轻微预备
      0,-0.06, 0.09,   0, 0.06,-0.09,
    ]);
    final rearStretch = _offset([
      0,-0.25, 0.4,    0, 0.25,-0.4,    // 前腿蹲下
      0, 0.35,-0.55,   0,-0.35, 0.55,   // 后腿伸展
    ]);
    // dart format on
    return GestureDefinition(
      name: 'stretch',
      description: '伸展',
      keyframes: [
        Keyframe(targetPose: crouchPose, counts: 12), // 微蹲蓄力
        Keyframe(targetPose: frontStretch, counts: 50), // 前伸
        Keyframe(targetPose: frontStretch, counts: 30), // 保持
        Keyframe(targetPose: standingPose, counts: 25), // 回中
        Keyframe(targetPose: rearAnti, counts: 10), // 预备
        Keyframe(targetPose: rearStretch, counts: 50), // 后伸
        Keyframe(targetPose: rearStretch, counts: 30), // 保持
        Keyframe(targetPose: standingPose, counts: 30), // 回位
      ],
    );
  }

  /// 跳舞：力量弹跳 → 大幅摇摆 → 身体波浪 → 爆发收尾。
  /// 120 BPM 节奏感，大幅度动作（hip ±0.45, thigh ±0.5）。
  GestureDefinition _dance() {
    // dart format off
    // ── 力量弹跳素材（快节奏 8 帧）──
    final crouch = _offset([
      0,-0.45, 0.68,   0, 0.45,-0.68,
      0, 0.45,-0.68,   0,-0.45, 0.68,
    ]);
    final springR = _offset([
      0.15, 0.3,-0.45,   0.15,-0.3, 0.45,
      0.15,-0.3, 0.45,   0.15, 0.3,-0.45,
    ]);
    final crouchL = _offset([
      -0.12,-0.45, 0.68,  -0.12, 0.45,-0.68,
      -0.12, 0.45,-0.68,  -0.12,-0.45, 0.68,
    ]);
    final springUp = _offset([
      0, 0.3,-0.45,   0,-0.3, 0.45,
      0,-0.3, 0.45,   0, 0.3,-0.45,
    ]);
    // ── 大幅摇摆素材（hip ±0.45）──
    final swayRDip = _offset([
      0.45,-0.15, 0.22,   0.45, 0.15,-0.22,
      0.45, 0.15,-0.22,   0.45,-0.15, 0.22,
    ]);
    final swayLDip = _offset([
      -0.45,-0.15, 0.22,  -0.45, 0.15,-0.22,
      -0.45, 0.15,-0.22,  -0.45,-0.15, 0.22,
    ]);
    final swayRBounce = _offset([
      0.4, 0.1,-0.15,   0.4,-0.1, 0.15,
      0.4,-0.1, 0.15,   0.4, 0.1,-0.15,
    ]);
    final swayLBounce = _offset([
      -0.4, 0.1,-0.15,  -0.4,-0.1, 0.15,
      -0.4,-0.1, 0.15,  -0.4, 0.1,-0.15,
    ]);
    // ── 身体波浪 + 扭转素材（thigh ±0.5, hip ±0.35）──
    final frontDip = _offset([
      0,-0.5, 0.75,   0, 0.5,-0.75,
      0,-0.15, 0.22,  0, 0.15,-0.22,
    ]);
    final rearDip = _offset([
      0, 0.15,-0.22,   0,-0.15, 0.22,
      0, 0.5,-0.75,    0,-0.5, 0.75,
    ]);
    final frontDipTwistR = _offset([
      -0.35,-0.4, 0.6,   -0.35, 0.4,-0.6,
      0.35,-0.15, 0.22,   0.35, 0.15,-0.22,
    ]);
    final rearDipTwistL = _offset([
      0.35,-0.4, 0.6,   0.35, 0.4,-0.6,
      -0.35,-0.15, 0.22, -0.35, 0.15,-0.22,
    ]);
    // ── 爆发收尾素材（最深蹲 thigh ±0.5）──
    final deepCrouch = _offset([
      0,-0.5, 0.75,   0, 0.5,-0.75,
      0, 0.5,-0.75,   0,-0.5, 0.75,
    ]);
    final endPose = _offset([
      0.35, 0.3,-0.45,   0.35,-0.3, 0.45,
      -0.25, 0.08,-0.12, -0.25,-0.08, 0.12,
    ]);
    // dart format on
    return GestureDefinition(
      name: 'dance',
      description: '跳舞',
      keyframes: [
        // Section 1: 力量弹跳
        Keyframe(targetPose: crouch, counts: 8), // 深蹲
        Keyframe(targetPose: springR, counts: 8), // 弹起 + 右倾
        Keyframe(targetPose: crouchL, counts: 8), // 深蹲 + 左倾
        Keyframe(targetPose: springUp, counts: 8), // 弹起
        // Section 2: 大幅摇摆
        Keyframe(targetPose: swayRDip, counts: 12), // 大右倾蹲
        Keyframe(targetPose: swayLDip, counts: 12), // 大左倾蹲
        Keyframe(targetPose: swayRBounce, counts: 10), // 大右倾弹
        Keyframe(targetPose: swayLBounce, counts: 10), // 大左倾弹
        // Section 3: 身体波浪 + 扭转
        Keyframe(targetPose: frontDip, counts: 12), // 深前俯
        Keyframe(targetPose: rearDip, counts: 12), // 深后仰
        Keyframe(targetPose: frontDipTwistR, counts: 12), // 前俯右扭
        Keyframe(targetPose: rearDipTwistL, counts: 12), // 后仰左扭
        // Section 4: 爆发收尾
        Keyframe(targetPose: deepCrouch, counts: 10), // 最深蹲蓄力
        Keyframe(targetPose: endPose, counts: 14), // 爆发弹起造型
        Keyframe(targetPose: endPose, counts: 25), // 保持造型
        Keyframe(targetPose: standingPose, counts: 25), // 回位
      ],
    );
  }
}
