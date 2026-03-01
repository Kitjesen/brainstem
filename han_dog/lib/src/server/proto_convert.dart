import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_message/han_dog_message.dart' as proto;
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart' as vm;

// ─── 基础类型转换 ────────────────────────────────────────────

extension VMVector3X on vm.Vector3 {
  proto.Vector3 toProto() => proto.Vector3(x: x, y: y, z: z);
}

extension VMQuaternionX on vm.Quaternion {
  /// Hamilton 约定: q = w + xi + yj + zk
  proto.Quaternion toProto() =>
      proto.Quaternion(w: w, x: x, y: y, z: z);
}

extension JointsMatrixX on JointsMatrix {
  proto.Matrix4 toProto() => proto.Matrix4(values: values);
}

// ─── History 转换 ────────────────────────────────────────────

extension HistoryX on History {
  proto.History toProto({
    proto.Duration? timestamp,
    JointsMatrix? kp,
    JointsMatrix? kd,
  }) =>
      proto.History(
        gyroscope: gyroscope.toProto(),
        projectedGravity: projectedGravity.toProto(),
        command: command.toProto(),
        jointPosition: jointPosition.toProto(),
        jointVelocity: jointVelocity.toProto(),
        action: action.toProto(),
        nextAction: nextAction.toProto(),
        timestamp: timestamp,
        kp: kp?.toProto(),
        kd: kd?.toProto(),
      );
}

// ─── Command 转换 ────────────────────────────────────────────

extension CommandX on Command {
  proto.Command toProto() => switch (this) {
        IdleCommand() => proto.Command(idle: proto.Empty()),
        StandUpCommand() => proto.Command(standUp: proto.Empty()),
        SitDownCommand() => proto.Command(sitDown: proto.Empty()),
        WalkCommand(:final direction) =>
          proto.Command(walk: direction.toProto()),
        // Gesture 暂无对应 proto 字段，映射为 idle + 注释标记
        GestureCommand() => proto.Command(idle: proto.Empty()),
      };
}

// ─── 传感器快照转换 ──────────────────────────────────────────

/// 从 [ImuService] 当前读数构造 [proto.Imu]。
/// [quaternion] 来自 [SimStateInjector.quaternion]（不在 ImuService 接口中）。
proto.Imu imuSnapshot(
  ImuService imu, {
  required vm.Quaternion quaternion,
  proto.Duration? timestamp,
}) =>
    proto.Imu(
      gyroscope: imu.gyroscope.toProto(),
      quaternion: quaternion.toProto(),
      timestamp: timestamp,
    );

/// 从 [JointService] 当前读数构造全量 [proto.Joint]。
/// 仿真模式力矩始终为零（JointService 接口不含 torque）。
proto.Joint jointSnapshot(
  JointService joint, {
  JointsMatrix? torque,
  proto.Duration? timestamp,
}) =>
    proto.Joint(
      allJoints: proto.AllJoints(
        position: joint.position.toProto(),
        velocity: joint.velocity.toProto(),
        torque: (torque ?? JointsMatrix.zero()).toProto(),
      ),
      timestamp: timestamp,
    );

// ─── SimState 反向转换（proto → core）────────────────────────

extension ProtoVector3X on proto.Vector3 {
  vm.Vector3 toVM() => vm.Vector3(x, y, z);
}

extension ProtoSimStateX on proto.SimState {
  /// 将 proto SimState 分解为 [SimStateInjector.injectSim] 所需的参数。
  void injectInto(SimStateInjector injector) => injector.injectSim(
        gyroscope: gyroscope.toVM(),
        quaternion: vm.Quaternion(
          quaternion.x,
          quaternion.y,
          quaternion.z,
          quaternion.w,
        ),
        position: JointsMatrix.fromList(
          jointPosition.values.map((v) => v.toDouble()).toList(),
        ),
        velocity: JointsMatrix.fromList(
          jointVelocity.values.map((v) => v.toDouble()).toList(),
        ),
      );
}
