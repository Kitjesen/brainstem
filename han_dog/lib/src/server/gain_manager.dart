import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

final _log = Logger('han_dog.gains');

/// 增益管理器：根据指令自动切换 PD 增益，并追踪当前增益。
///
/// 用法：
/// ```dart
/// final gains = GainManager(
///   inferKp: inferKp, inferKd: inferKd,
///   standUpKp: standUpKp, standUpKd: standUpKd,
///   sitDownKp: sitDownKp, sitDownKd: sitDownKd,
/// );
/// gains.applyCommand(A.walk(...));
/// print(gains.kp); // → inferKp
/// ```
class GainManager {
  JointsMatrix inferKp;
  JointsMatrix inferKd;
  JointsMatrix standUpKp;
  JointsMatrix standUpKd;
  JointsMatrix sitDownKp;
  JointsMatrix sitDownKd;

  /// 当前 kp/kd（初始值为推理增益）。
  JointsMatrix kp;
  JointsMatrix kd;

  /// 增益变更时的回调（可选，例如同步到 SimJoint.kp/kd）。
  final void Function(JointsMatrix kp, JointsMatrix kd)? onChanged;

  GainManager({
    required this.inferKp,
    required this.inferKd,
    required this.standUpKp,
    required this.standUpKd,
    required this.sitDownKp,
    required this.sitDownKd,
    this.onChanged,
  })  : kp = inferKp,
        kd = inferKd;

  /// 切换策略时更新全部增益参数（profile 级别，非逐指令切换）。
  void switchGains({
    required JointsMatrix inferKp,
    required JointsMatrix inferKd,
    required JointsMatrix standUpKp,
    required JointsMatrix standUpKd,
    required JointsMatrix sitDownKp,
    required JointsMatrix sitDownKd,
  }) {
    this.inferKp = inferKp;
    this.inferKd = inferKd;
    this.standUpKp = standUpKp;
    this.standUpKd = standUpKd;
    this.sitDownKp = sitDownKp;
    this.sitDownKd = sitDownKd;
    _log.fine('Gains profile updated (full set switched)');
  }

  /// 根据指令切换增益；增益未变时不触发 [onChanged]。
  void applyCommand(A action) {
    JointsMatrix? newKp;
    JointsMatrix? newKd;
    switch (action) {
      case CmdWalk():
        newKp = inferKp;
        newKd = inferKd;
      case CmdStandUp():
        newKp = standUpKp;
        newKd = standUpKd;
      case CmdSitDown():
        newKp = sitDownKp;
        newKd = sitDownKd;
      case CmdGesture():
        // 动作使用 standUp 增益（站立状态下的低速运动）
        newKp = standUpKp;
        newKd = standUpKd;
      default:
        return; // Idle/Init/Fault/Done 不切换增益
    }
    if (identical(kp, newKp) && identical(kd, newKd)) return;
    // flow analysis guarantees newKp/newKd non-null here (default: return above)
    kp = newKp; // ignore: unnecessary_non_null_assertion
    kd = newKd;
    _log.fine('增益切换 → ${action.runtimeType}');
    onChanged?.call(kp, kd);
  }
}
