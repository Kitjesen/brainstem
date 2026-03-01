import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

final _log = Logger('han_dog_brain.gesture');

/// 关键帧：一个目标姿态 + 到达该姿态的插值帧数。
class Keyframe {
  final JointsMatrix targetPose;

  /// 从上一姿态插值到 [targetPose] 所需的帧数。
  /// 0 表示立即到达（1 帧，t=1.0）。
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
    counts: json['counts'] as int,
  );
}

/// 动作定义：一组关键帧序列。
class GestureDefinition {
  final String name;
  final String? description;
  final List<Keyframe> keyframes;

  const GestureDefinition({
    required this.name,
    this.description,
    required this.keyframes,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };

  factory GestureDefinition.fromJson(Map<String, dynamic> json) =>
      GestureDefinition(
        name: json['name'] as String,
        description: json['description'] as String?,
        keyframes: (json['keyframes'] as List)
            .map((k) => Keyframe.fromJson(k as Map<String, dynamic>))
            .toList(),
      );
}

/// 动作库：存储和管理命名动作定义。
class GestureLibrary {
  final Map<String, GestureDefinition> _gestures = {};
  final JointsMatrix standingPose;

  GestureLibrary({required this.standingPose});

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
      final list = jsonDecode(jsonString) as List;
      for (final item in list) {
        register(GestureDefinition.fromJson(item as Map<String, dynamic>));
      }
    } catch (e, st) {
      _log.warning('loadFromJson failed', e, st);
      rethrow;
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
      v[0] + offsets[0], v[1] + offsets[1], v[2] + offsets[2],
      v[3] + offsets[3], v[4] + offsets[4], v[5] + offsets[5],
      v[6] + offsets[6], v[7] + offsets[7], v[8] + offsets[8],
      v[9] + offsets[9], v[10] + offsets[10], v[11] + offsets[11],
      0, 0, 0, 0,
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
        Keyframe(targetPose: antiPose, counts: 15),        // 预备上抬
        Keyframe(targetPose: bowPose, counts: 55),         // 鞠躬
        Keyframe(targetPose: bowPose, counts: 50),         // 保持
        Keyframe(targetPose: standingPose, counts: 60),    // 起身
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
        Keyframe(targetPose: nodDeep, counts: 20),         // 第一次深点头
        Keyframe(targetPose: nodOvershoot, counts: 15),    // 过冲回弹
        Keyframe(targetPose: nodLight, counts: 18),        // 第二次浅点头
        Keyframe(targetPose: standingPose, counts: 12),    // 回位
        Keyframe(targetPose: nodTiny, counts: 10),         // 第三次微点头
        Keyframe(targetPose: standingPose, counts: 12),    // 最终回位
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
        Keyframe(targetPose: smallL, counts: 12),   // 小左
        Keyframe(targetPose: smallR, counts: 12),   // 小右
        Keyframe(targetPose: medL, counts: 15),     // 中左
        Keyframe(targetPose: medR, counts: 15),     // 中右
        Keyframe(targetPose: fullL, counts: 18),    // 大左
        Keyframe(targetPose: fullR, counts: 18),    // 大右
        Keyframe(targetPose: medL, counts: 15),     // 中左
        Keyframe(targetPose: smallR, counts: 12),   // 小右
        Keyframe(targetPose: standingPose, counts: 10),  // 回位
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
        Keyframe(targetPose: crouchPose, counts: 12),        // 微蹲蓄力
        Keyframe(targetPose: frontStretch, counts: 50),      // 前伸
        Keyframe(targetPose: frontStretch, counts: 30),      // 保持
        Keyframe(targetPose: standingPose, counts: 25),      // 回中
        Keyframe(targetPose: rearAnti, counts: 10),          // 预备
        Keyframe(targetPose: rearStretch, counts: 50),       // 后伸
        Keyframe(targetPose: rearStretch, counts: 30),       // 保持
        Keyframe(targetPose: standingPose, counts: 30),      // 回位
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
        Keyframe(targetPose: crouch, counts: 8),        // 深蹲
        Keyframe(targetPose: springR, counts: 8),       // 弹起 + 右倾
        Keyframe(targetPose: crouchL, counts: 8),       // 深蹲 + 左倾
        Keyframe(targetPose: springUp, counts: 8),      // 弹起
        // Section 2: 大幅摇摆
        Keyframe(targetPose: swayRDip, counts: 12),     // 大右倾蹲
        Keyframe(targetPose: swayLDip, counts: 12),     // 大左倾蹲
        Keyframe(targetPose: swayRBounce, counts: 10),  // 大右倾弹
        Keyframe(targetPose: swayLBounce, counts: 10),  // 大左倾弹
        // Section 3: 身体波浪 + 扭转
        Keyframe(targetPose: frontDip, counts: 12),     // 深前俯
        Keyframe(targetPose: rearDip, counts: 12),      // 深后仰
        Keyframe(targetPose: frontDipTwistR, counts: 12), // 前俯右扭
        Keyframe(targetPose: rearDipTwistL, counts: 12),  // 后仰左扭
        // Section 4: 爆发收尾
        Keyframe(targetPose: deepCrouch, counts: 10),   // 最深蹲蓄力
        Keyframe(targetPose: endPose, counts: 14),      // 爆发弹起造型
        Keyframe(targetPose: endPose, counts: 25),      // 保持造型
        Keyframe(targetPose: standingPose, counts: 25), // 回位
      ],
    );
  }
}
