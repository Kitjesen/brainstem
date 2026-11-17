// 手柄抽象接口 — YUNZHUO 和 Xbox 共用。
//
// RealControlDog 消费此接口，不关心底层是 YUNZHUO 串口还是 Xbox USB。

import 'package:vector_math/vector_math.dart';

/// 手柄控制器抽象：提供方向、按钮流。
abstract class Gamepad {
  /// 行走方向流：(x=前后, y=左右, z=旋转)
  Stream<Vector3> get direction;

  /// StandUp 按钮
  Stream<bool> get standup;

  /// SitDown 按钮
  Stream<bool> get sitdown;

  /// 电机使能切换
  Stream<bool> get enabled;

  /// Idle (停止行走回站立)
  Stream<bool> get idle;

  /// 紧急停止
  Stream<bool> get red;

  /// 标零组合键
  Stream<void> get calibrate;

  /// 策略切换
  Stream<void> get switchProfile;

  void dispose();
}

/// 可报告“必须绕过普通平滑并立即归零”的物理控制器。
///
/// 例如 SBUS 超过看门狗时限或串口断开。人为 CH5 切档不走此通道。
abstract interface class HardStopGamepad {
  Stream<void> get hardStop;
  bool get hardStopActive; // 仅新收到的真实遥控帧可以解除输入超时。
}

/// Optional health surface used by boot self-checks.
///
/// Keeping this separate from [Gamepad] lets future input backends expose
/// richer diagnostics without forcing command-stream changes.
abstract interface class InputHealthGamepad {
  bool get inputHealthy;
  int get inputHz;
}
