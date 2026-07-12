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

  /// Synchronizes a controller-local enable latch with the authoritative
  /// motor-output state. Controllers without a local latch may ignore it.
  void syncMotorOutputEnabled(bool enabled) {}

  void dispose();
}
