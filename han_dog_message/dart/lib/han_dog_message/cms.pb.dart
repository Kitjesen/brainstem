// This is a generated file - do not edit.
//
// Generated from han_dog_message/cms.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as $4;
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart' as $0;

import 'common.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// 单次推理周期的完整观测数据（RL policy 的输入/输出）。
class History extends $pb.GeneratedMessage {
  factory History({
    $1.Vector3? gyroscope,
    $1.Vector3? projectedGravity,
    Command? command,
    $1.Matrix4? jointPosition,
    $1.Matrix4? jointVelocity,
    $1.Matrix4? action,
    $1.Matrix4? nextAction,
    $4.Duration? timestamp,
    $1.Matrix4? kp,
    $1.Matrix4? kd,
  }) {
    final result = create();
    if (gyroscope != null) result.gyroscope = gyroscope;
    if (projectedGravity != null) result.projectedGravity = projectedGravity;
    if (command != null) result.command = command;
    if (jointPosition != null) result.jointPosition = jointPosition;
    if (jointVelocity != null) result.jointVelocity = jointVelocity;
    if (action != null) result.action = action;
    if (nextAction != null) result.nextAction = nextAction;
    if (timestamp != null) result.timestamp = timestamp;
    if (kp != null) result.kp = kp;
    if (kd != null) result.kd = kd;
    return result;
  }

  History._();

  factory History.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory History.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'History',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOM<$1.Vector3>(1, _omitFieldNames ? '' : 'gyroscope',
        subBuilder: $1.Vector3.create)
    ..aOM<$1.Vector3>(2, _omitFieldNames ? '' : 'projectedGravity',
        subBuilder: $1.Vector3.create)
    ..aOM<Command>(3, _omitFieldNames ? '' : 'command',
        subBuilder: Command.create)
    ..aOM<$1.Matrix4>(4, _omitFieldNames ? '' : 'jointPosition',
        subBuilder: $1.Matrix4.create)
    ..aOM<$1.Matrix4>(5, _omitFieldNames ? '' : 'jointVelocity',
        subBuilder: $1.Matrix4.create)
    ..aOM<$1.Matrix4>(6, _omitFieldNames ? '' : 'action',
        subBuilder: $1.Matrix4.create)
    ..aOM<$1.Matrix4>(7, _omitFieldNames ? '' : 'nextAction',
        subBuilder: $1.Matrix4.create)
    ..aOM<$4.Duration>(8, _omitFieldNames ? '' : 'timestamp',
        subBuilder: $4.Duration.create)
    ..aOM<$1.Matrix4>(9, _omitFieldNames ? '' : 'kp',
        subBuilder: $1.Matrix4.create)
    ..aOM<$1.Matrix4>(10, _omitFieldNames ? '' : 'kd',
        subBuilder: $1.Matrix4.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  History clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  History copyWith(void Function(History) updates) =>
      super.copyWith((message) => updates(message as History)) as History;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static History create() => History._();
  @$core.override
  History createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static History getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<History>(create);
  static History? _defaultInstance;

  /// IMU 角速度 (rad/s)，body frame。
  @$pb.TagNumber(1)
  $1.Vector3 get gyroscope => $_getN(0);
  @$pb.TagNumber(1)
  set gyroscope($1.Vector3 value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasGyroscope() => $_has(0);
  @$pb.TagNumber(1)
  void clearGyroscope() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Vector3 ensureGyroscope() => $_ensure(0);

  /// 重力在 body frame 下的投影（单位向量，静止时为 [0, 0, -1]）。
  @$pb.TagNumber(2)
  $1.Vector3 get projectedGravity => $_getN(1);
  @$pb.TagNumber(2)
  set projectedGravity($1.Vector3 value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasProjectedGravity() => $_has(1);
  @$pb.TagNumber(2)
  void clearProjectedGravity() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Vector3 ensureProjectedGravity() => $_ensure(1);

  /// 当前运动指令。
  @$pb.TagNumber(3)
  Command get command => $_getN(2);
  @$pb.TagNumber(3)
  set command(Command value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCommand() => $_has(2);
  @$pb.TagNumber(3)
  void clearCommand() => $_clearField(3);
  @$pb.TagNumber(3)
  Command ensureCommand() => $_ensure(2);

  /// 当前关节角度 (rad)。
  @$pb.TagNumber(4)
  $1.Matrix4 get jointPosition => $_getN(3);
  @$pb.TagNumber(4)
  set jointPosition($1.Matrix4 value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasJointPosition() => $_has(3);
  @$pb.TagNumber(4)
  void clearJointPosition() => $_clearField(4);
  @$pb.TagNumber(4)
  $1.Matrix4 ensureJointPosition() => $_ensure(3);

  /// 当前关节角速度 (rad/s)。
  @$pb.TagNumber(5)
  $1.Matrix4 get jointVelocity => $_getN(4);
  @$pb.TagNumber(5)
  set jointVelocity($1.Matrix4 value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasJointVelocity() => $_has(4);
  @$pb.TagNumber(5)
  void clearJointVelocity() => $_clearField(5);
  @$pb.TagNumber(5)
  $1.Matrix4 ensureJointVelocity() => $_ensure(4);

  /// 上一步 policy 输出的目标关节角度 (rad)。
  @$pb.TagNumber(6)
  $1.Matrix4 get action => $_getN(5);
  @$pb.TagNumber(6)
  set action($1.Matrix4 value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasAction() => $_has(5);
  @$pb.TagNumber(6)
  void clearAction() => $_clearField(6);
  @$pb.TagNumber(6)
  $1.Matrix4 ensureAction() => $_ensure(5);

  /// 当前步 policy 输出的目标关节角度 (rad)。
  @$pb.TagNumber(7)
  $1.Matrix4 get nextAction => $_getN(6);
  @$pb.TagNumber(7)
  set nextAction($1.Matrix4 value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasNextAction() => $_has(6);
  @$pb.TagNumber(7)
  void clearNextAction() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.Matrix4 ensureNextAction() => $_ensure(6);

  /// 相对于会话开始时间的时间戳。
  @$pb.TagNumber(8)
  $4.Duration get timestamp => $_getN(7);
  @$pb.TagNumber(8)
  set timestamp($4.Duration value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasTimestamp() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimestamp() => $_clearField(8);
  @$pb.TagNumber(8)
  $4.Duration ensureTimestamp() => $_ensure(7);

  /// 当前 PD 控制器的比例增益（16 个关节）。
  @$pb.TagNumber(9)
  $1.Matrix4 get kp => $_getN(8);
  @$pb.TagNumber(9)
  set kp($1.Matrix4 value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasKp() => $_has(8);
  @$pb.TagNumber(9)
  void clearKp() => $_clearField(9);
  @$pb.TagNumber(9)
  $1.Matrix4 ensureKp() => $_ensure(8);

  /// 当前 PD 控制器的微分增益（16 个关节）。
  @$pb.TagNumber(10)
  $1.Matrix4 get kd => $_getN(9);
  @$pb.TagNumber(10)
  set kd($1.Matrix4 value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasKd() => $_has(9);
  @$pb.TagNumber(10)
  void clearKd() => $_clearField(10);
  @$pb.TagNumber(10)
  $1.Matrix4 ensureKd() => $_ensure(9);
}

/// IMU 传感器数据。
class Imu extends $pb.GeneratedMessage {
  factory Imu({
    $1.Vector3? gyroscope,
    $1.Quaternion? quaternion,
    $4.Duration? timestamp,
  }) {
    final result = create();
    if (gyroscope != null) result.gyroscope = gyroscope;
    if (quaternion != null) result.quaternion = quaternion;
    if (timestamp != null) result.timestamp = timestamp;
    return result;
  }

  Imu._();

  factory Imu.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Imu.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Imu',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOM<$1.Vector3>(1, _omitFieldNames ? '' : 'gyroscope',
        subBuilder: $1.Vector3.create)
    ..aOM<$1.Quaternion>(2, _omitFieldNames ? '' : 'quaternion',
        subBuilder: $1.Quaternion.create)
    ..aOM<$4.Duration>(3, _omitFieldNames ? '' : 'timestamp',
        subBuilder: $4.Duration.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Imu clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Imu copyWith(void Function(Imu) updates) =>
      super.copyWith((message) => updates(message as Imu)) as Imu;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Imu create() => Imu._();
  @$core.override
  Imu createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Imu getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Imu>(create);
  static Imu? _defaultInstance;

  /// 角速度 (rad/s)，body frame。
  @$pb.TagNumber(1)
  $1.Vector3 get gyroscope => $_getN(0);
  @$pb.TagNumber(1)
  set gyroscope($1.Vector3 value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasGyroscope() => $_has(0);
  @$pb.TagNumber(1)
  void clearGyroscope() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Vector3 ensureGyroscope() => $_ensure(0);

  /// 姿态四元数（world → body 旋转）。
  @$pb.TagNumber(2)
  $1.Quaternion get quaternion => $_getN(1);
  @$pb.TagNumber(2)
  set quaternion($1.Quaternion value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasQuaternion() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuaternion() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Quaternion ensureQuaternion() => $_ensure(1);

  /// 相对于会话开始时间的时间戳。
  @$pb.TagNumber(3)
  $4.Duration get timestamp => $_getN(2);
  @$pb.TagNumber(3)
  set timestamp($4.Duration value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestamp() => $_clearField(3);
  @$pb.TagNumber(3)
  $4.Duration ensureTimestamp() => $_ensure(2);
}

enum Joint_Data { singleJoint, allJoints, notSet }

/// 关节数据（支持单关节上报和全关节快照两种模式）。
class Joint extends $pb.GeneratedMessage {
  factory Joint({
    SingleJoint? singleJoint,
    AllJoints? allJoints,
    $4.Duration? timestamp,
  }) {
    final result = create();
    if (singleJoint != null) result.singleJoint = singleJoint;
    if (allJoints != null) result.allJoints = allJoints;
    if (timestamp != null) result.timestamp = timestamp;
    return result;
  }

  Joint._();

  factory Joint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Joint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Joint_Data> _Joint_DataByTag = {
    1: Joint_Data.singleJoint,
    2: Joint_Data.allJoints,
    0: Joint_Data.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Joint',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..oo(0, [1, 2])
    ..aOM<SingleJoint>(1, _omitFieldNames ? '' : 'singleJoint',
        subBuilder: SingleJoint.create)
    ..aOM<AllJoints>(2, _omitFieldNames ? '' : 'allJoints',
        subBuilder: AllJoints.create)
    ..aOM<$4.Duration>(3, _omitFieldNames ? '' : 'timestamp',
        subBuilder: $4.Duration.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Joint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Joint copyWith(void Function(Joint) updates) =>
      super.copyWith((message) => updates(message as Joint)) as Joint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Joint create() => Joint._();
  @$core.override
  Joint createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Joint getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Joint>(create);
  static Joint? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  Joint_Data whichData() => _Joint_DataByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearData() => $_clearField($_whichOneof(0));

  /// 单个关节的状态上报（CAN 总线逐个上报时使用）。
  @$pb.TagNumber(1)
  SingleJoint get singleJoint => $_getN(0);
  @$pb.TagNumber(1)
  set singleJoint(SingleJoint value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSingleJoint() => $_has(0);
  @$pb.TagNumber(1)
  void clearSingleJoint() => $_clearField(1);
  @$pb.TagNumber(1)
  SingleJoint ensureSingleJoint() => $_ensure(0);

  /// 全部 16 个关节的聚合快照。
  @$pb.TagNumber(2)
  AllJoints get allJoints => $_getN(1);
  @$pb.TagNumber(2)
  set allJoints(AllJoints value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAllJoints() => $_has(1);
  @$pb.TagNumber(2)
  void clearAllJoints() => $_clearField(2);
  @$pb.TagNumber(2)
  AllJoints ensureAllJoints() => $_ensure(1);

  /// 相对于会话开始时间的时间戳。
  @$pb.TagNumber(3)
  $4.Duration get timestamp => $_getN(2);
  @$pb.TagNumber(3)
  set timestamp($4.Duration value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestamp() => $_clearField(3);
  @$pb.TagNumber(3)
  $4.Duration ensureTimestamp() => $_ensure(2);
}

/// 单个关节的状态。
class SingleJoint extends $pb.GeneratedMessage {
  factory SingleJoint({
    $core.int? id,
    $core.double? position,
    $core.double? velocity,
    $core.double? torque,
    $core.int? status,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (position != null) result.position = position;
    if (velocity != null) result.velocity = velocity;
    if (torque != null) result.torque = torque;
    if (status != null) result.status = status;
    return result;
  }

  SingleJoint._();

  factory SingleJoint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SingleJoint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SingleJoint',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id', fieldType: $pb.PbFieldType.OU3)
    ..aD(2, _omitFieldNames ? '' : 'position', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'velocity', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'torque', fieldType: $pb.PbFieldType.OF)
    ..aI(5, _omitFieldNames ? '' : 'status', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SingleJoint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SingleJoint copyWith(void Function(SingleJoint) updates) =>
      super.copyWith((message) => updates(message as SingleJoint))
          as SingleJoint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SingleJoint create() => SingleJoint._();
  @$core.override
  SingleJoint createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SingleJoint getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SingleJoint>(create);
  static SingleJoint? _defaultInstance;

  /// 关节 ID（参见 Matrix4 的关节索引 0-15）。
  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// 关节角度 (rad)。
  @$pb.TagNumber(2)
  $core.double get position => $_getN(1);
  @$pb.TagNumber(2)
  set position($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPosition() => $_has(1);
  @$pb.TagNumber(2)
  void clearPosition() => $_clearField(2);

  /// 关节角速度 (rad/s)。
  @$pb.TagNumber(3)
  $core.double get velocity => $_getN(2);
  @$pb.TagNumber(3)
  set velocity($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVelocity() => $_has(2);
  @$pb.TagNumber(3)
  void clearVelocity() => $_clearField(3);

  /// 关节力矩 (N·m)。
  @$pb.TagNumber(4)
  $core.double get torque => $_getN(3);
  @$pb.TagNumber(4)
  set torque($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTorque() => $_has(3);
  @$pb.TagNumber(4)
  void clearTorque() => $_clearField(4);

  /// 电机状态码（具体含义取决于电机驱动协议）。
  @$pb.TagNumber(5)
  $core.int get status => $_getIZ(4);
  @$pb.TagNumber(5)
  set status($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStatus() => $_has(4);
  @$pb.TagNumber(5)
  void clearStatus() => $_clearField(5);
}

/// 全部关节的聚合快照。
class AllJoints extends $pb.GeneratedMessage {
  factory AllJoints({
    $1.Matrix4? position,
    $1.Matrix4? velocity,
    $1.Matrix4? torque,
    $1.Matrix4Int32? status,
  }) {
    final result = create();
    if (position != null) result.position = position;
    if (velocity != null) result.velocity = velocity;
    if (torque != null) result.torque = torque;
    if (status != null) result.status = status;
    return result;
  }

  AllJoints._();

  factory AllJoints.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AllJoints.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AllJoints',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOM<$1.Matrix4>(1, _omitFieldNames ? '' : 'position',
        subBuilder: $1.Matrix4.create)
    ..aOM<$1.Matrix4>(2, _omitFieldNames ? '' : 'velocity',
        subBuilder: $1.Matrix4.create)
    ..aOM<$1.Matrix4>(3, _omitFieldNames ? '' : 'torque',
        subBuilder: $1.Matrix4.create)
    ..aOM<$1.Matrix4Int32>(4, _omitFieldNames ? '' : 'status',
        subBuilder: $1.Matrix4Int32.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AllJoints clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AllJoints copyWith(void Function(AllJoints) updates) =>
      super.copyWith((message) => updates(message as AllJoints)) as AllJoints;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AllJoints create() => AllJoints._();
  @$core.override
  AllJoints createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AllJoints getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AllJoints>(create);
  static AllJoints? _defaultInstance;

  /// 16 个关节角度 (rad)。
  @$pb.TagNumber(1)
  $1.Matrix4 get position => $_getN(0);
  @$pb.TagNumber(1)
  set position($1.Matrix4 value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Matrix4 ensurePosition() => $_ensure(0);

  /// 16 个关节角速度 (rad/s)。
  @$pb.TagNumber(2)
  $1.Matrix4 get velocity => $_getN(1);
  @$pb.TagNumber(2)
  set velocity($1.Matrix4 value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasVelocity() => $_has(1);
  @$pb.TagNumber(2)
  void clearVelocity() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Matrix4 ensureVelocity() => $_ensure(1);

  /// 16 个关节力矩 (N·m)。
  @$pb.TagNumber(3)
  $1.Matrix4 get torque => $_getN(2);
  @$pb.TagNumber(3)
  set torque($1.Matrix4 value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTorque() => $_has(2);
  @$pb.TagNumber(3)
  void clearTorque() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.Matrix4 ensureTorque() => $_ensure(2);

  /// 16 个电机状态码。
  @$pb.TagNumber(4)
  $1.Matrix4Int32 get status => $_getN(3);
  @$pb.TagNumber(4)
  set status($1.Matrix4Int32 value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => $_clearField(4);
  @$pb.TagNumber(4)
  $1.Matrix4Int32 ensureStatus() => $_ensure(3);
}

/// 机器人参数查询响应。
class Params extends $pb.GeneratedMessage {
  factory Params({
    $1.RobotModel? robot,
  }) {
    final result = create();
    if (robot != null) result.robot = robot;
    return result;
  }

  Params._();

  factory Params.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Params.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Params',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOM<$1.RobotModel>(1, _omitFieldNames ? '' : 'robot',
        subBuilder: $1.RobotModel.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Params clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Params copyWith(void Function(Params) updates) =>
      super.copyWith((message) => updates(message as Params)) as Params;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Params create() => Params._();
  @$core.override
  Params createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Params getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Params>(create);
  static Params? _defaultInstance;

  /// 当前机器人模型参数。
  @$pb.TagNumber(1)
  $1.RobotModel get robot => $_getN(0);
  @$pb.TagNumber(1)
  set robot($1.RobotModel value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRobot() => $_has(0);
  @$pb.TagNumber(1)
  void clearRobot() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.RobotModel ensureRobot() => $_ensure(0);
}

/// 策略切换请求。
class ProfileRequest extends $pb.GeneratedMessage {
  factory ProfileRequest({
    $core.String? name,
  }) {
    final result = create();
    if (name != null) result.name = name;
    return result;
  }

  ProfileRequest._();

  factory ProfileRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProfileRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProfileRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProfileRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProfileRequest copyWith(void Function(ProfileRequest) updates) =>
      super.copyWith((message) => updates(message as ProfileRequest))
          as ProfileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProfileRequest create() => ProfileRequest._();
  @$core.override
  ProfileRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProfileRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProfileRequest>(create);
  static ProfileRequest? _defaultInstance;

  /// 目标策略名称。
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);
}

/// 策略信息（当前策略名称 + 可用策略列表 + 说明）。
class ProfileInfo extends $pb.GeneratedMessage {
  factory ProfileInfo({
    $core.String? current,
    $core.Iterable<$core.String>? available,
    $core.Iterable<$core.String>? descriptions,
    $core.String? currentDescription,
  }) {
    final result = create();
    if (current != null) result.current = current;
    if (available != null) result.available.addAll(available);
    if (descriptions != null) result.descriptions.addAll(descriptions);
    if (currentDescription != null)
      result.currentDescription = currentDescription;
    return result;
  }

  ProfileInfo._();

  factory ProfileInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProfileInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProfileInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'current')
    ..pPS(2, _omitFieldNames ? '' : 'available')
    ..pPS(3, _omitFieldNames ? '' : 'descriptions')
    ..aOS(4, _omitFieldNames ? '' : 'currentDescription')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProfileInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProfileInfo copyWith(void Function(ProfileInfo) updates) =>
      super.copyWith((message) => updates(message as ProfileInfo))
          as ProfileInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProfileInfo create() => ProfileInfo._();
  @$core.override
  ProfileInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProfileInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProfileInfo>(create);
  static ProfileInfo? _defaultInstance;

  /// 当前激活的策略名称。
  @$pb.TagNumber(1)
  $core.String get current => $_getSZ(0);
  @$pb.TagNumber(1)
  set current($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrent() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrent() => $_clearField(1);

  /// 所有可用策略名称（与 descriptions 按索引对应）。
  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get available => $_getList(1);

  /// 各策略的说明（与 available 并列）。
  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get descriptions => $_getList(2);

  /// 当前策略的说明。
  @$pb.TagNumber(4)
  $core.String get currentDescription => $_getSZ(3);
  @$pb.TagNumber(4)
  set currentDescription($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrentDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrentDescription() => $_clearField(4);
}

enum Command_Data { idle, standUp, sitDown, walk, notSet }

/// 运动指令。
class Command extends $pb.GeneratedMessage {
  factory Command({
    $0.Empty? idle,
    $0.Empty? standUp,
    $0.Empty? sitDown,
    $1.Vector3? walk,
  }) {
    final result = create();
    if (idle != null) result.idle = idle;
    if (standUp != null) result.standUp = standUp;
    if (sitDown != null) result.sitDown = sitDown;
    if (walk != null) result.walk = walk;
    return result;
  }

  Command._();

  factory Command.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Command.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Command_Data> _Command_DataByTag = {
    1: Command_Data.idle,
    2: Command_Data.standUp,
    3: Command_Data.sitDown,
    4: Command_Data.walk,
    0: Command_Data.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Command',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<$0.Empty>(1, _omitFieldNames ? '' : 'idle',
        subBuilder: $0.Empty.create)
    ..aOM<$0.Empty>(2, _omitFieldNames ? '' : 'standUp',
        subBuilder: $0.Empty.create)
    ..aOM<$0.Empty>(3, _omitFieldNames ? '' : 'sitDown',
        subBuilder: $0.Empty.create)
    ..aOM<$1.Vector3>(4, _omitFieldNames ? '' : 'walk',
        subBuilder: $1.Vector3.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command copyWith(void Function(Command) updates) =>
      super.copyWith((message) => updates(message as Command)) as Command;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Command create() => Command._();
  @$core.override
  Command createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Command getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Command>(create);
  static Command? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  Command_Data whichData() => _Command_DataByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearData() => $_clearField($_whichOneof(0));

  /// 空闲：保持当前姿态，不进行推理。
  @$pb.TagNumber(1)
  $0.Empty get idle => $_getN(0);
  @$pb.TagNumber(1)
  set idle($0.Empty value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasIdle() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdle() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Empty ensureIdle() => $_ensure(0);

  /// 站起：从坐姿平滑过渡到站立姿态。
  @$pb.TagNumber(2)
  $0.Empty get standUp => $_getN(1);
  @$pb.TagNumber(2)
  set standUp($0.Empty value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStandUp() => $_has(1);
  @$pb.TagNumber(2)
  void clearStandUp() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Empty ensureStandUp() => $_ensure(1);

  /// 坐下：从站立平滑过渡到坐姿。
  @$pb.TagNumber(3)
  $0.Empty get sitDown => $_getN(2);
  @$pb.TagNumber(3)
  set sitDown($0.Empty value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSitDown() => $_has(2);
  @$pb.TagNumber(3)
  void clearSitDown() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Empty ensureSitDown() => $_ensure(2);

  /// 行走：(x=前后, y=左右, z=旋转)，范围 [-1, 1]。
  @$pb.TagNumber(4)
  $1.Vector3 get walk => $_getN(3);
  @$pb.TagNumber(4)
  set walk($1.Vector3 value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasWalk() => $_has(3);
  @$pb.TagNumber(4)
  void clearWalk() => $_clearField(4);
  @$pb.TagNumber(4)
  $1.Vector3 ensureWalk() => $_ensure(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
