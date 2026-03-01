import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vector_math/vector_math.dart';

part 'a.freezed.dart';

@freezed
sealed class A with _$A {
  const factory A.init() = Init;
  const factory A.standUp() = CmdStandUp;
  const factory A.sitDown() = CmdSitDown;
  const factory A.walk(Vector3 direction) = CmdWalk;
  /// 主动回到站立（Walking 摇杆归零超时后使用）。
  const factory A.idle() = CmdIdle;
  const factory A.gesture(String name) = CmdGesture;
  const factory A.fault(String reason) = Fault;
  const factory A.done() = Done;
}
