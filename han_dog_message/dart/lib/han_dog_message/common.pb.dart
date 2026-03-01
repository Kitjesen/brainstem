// This is a generated file - do not edit.
//
// Generated from han_dog_message/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as $0;

import 'common.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'common.pbenum.dart';

/// 三维向量，含义由使用场景决定（见各字段注释）。
class Vector3 extends $pb.GeneratedMessage {
  factory Vector3({
    $core.double? x,
    $core.double? y,
    $core.double? z,
  }) {
    final result = create();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (z != null) result.z = z;
    return result;
  }

  Vector3._();

  factory Vector3.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Vector3.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Vector3',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'z', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Vector3 clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Vector3 copyWith(void Function(Vector3) updates) =>
      super.copyWith((message) => updates(message as Vector3)) as Vector3;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Vector3 create() => Vector3._();
  @$core.override
  Vector3 createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Vector3 getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Vector3>(create);
  static Vector3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get x => $_getN(0);
  @$pb.TagNumber(1)
  set x($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get y => $_getN(1);
  @$pb.TagNumber(2)
  set y($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get z => $_getN(2);
  @$pb.TagNumber(3)
  set z($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasZ() => $_has(2);
  @$pb.TagNumber(3)
  void clearZ() => $_clearField(3);
}

/// 可变长度浮点数组。
class ArrayFloat extends $pb.GeneratedMessage {
  factory ArrayFloat({
    $core.Iterable<$core.double>? values,
  }) {
    final result = create();
    if (values != null) result.values.addAll(values);
    return result;
  }

  ArrayFloat._();

  factory ArrayFloat.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ArrayFloat.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ArrayFloat',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..p<$core.double>(1, _omitFieldNames ? '' : 'values', $pb.PbFieldType.KF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArrayFloat clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArrayFloat copyWith(void Function(ArrayFloat) updates) =>
      super.copyWith((message) => updates(message as ArrayFloat)) as ArrayFloat;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ArrayFloat create() => ArrayFloat._();
  @$core.override
  ArrayFloat createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ArrayFloat getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ArrayFloat>(create);
  static ArrayFloat? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get values => $_getList(0);
}

/// 四足机器人 16 个关节值的扁平数组。
///
/// 关节顺序（索引 0-15）：
///   [ 0] FR_hip    [ 1] FR_thigh  [ 2] FR_calf
///   [ 3] FL_hip    [ 4] FL_thigh  [ 5] FL_calf
///   [ 6] RR_hip    [ 7] RR_thigh  [ 8] RR_calf
///   [ 9] RL_hip    [10] RL_thigh  [11] RL_calf
///   [12] FR_foot   [13] FL_foot   [14] RR_foot   [15] RL_foot
///
/// 其中 FR=前右, FL=前左, RR=后右, RL=后左。
/// hip=髋关节, thigh=大腿, calf=小腿, foot=脚踝。
class Matrix4 extends $pb.GeneratedMessage {
  factory Matrix4({
    $core.Iterable<$core.double>? values,
  }) {
    final result = create();
    if (values != null) result.values.addAll(values);
    return result;
  }

  Matrix4._();

  factory Matrix4.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Matrix4.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Matrix4',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..p<$core.double>(1, _omitFieldNames ? '' : 'values', $pb.PbFieldType.KF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Matrix4 clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Matrix4 copyWith(void Function(Matrix4) updates) =>
      super.copyWith((message) => updates(message as Matrix4)) as Matrix4;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Matrix4 create() => Matrix4._();
  @$core.override
  Matrix4 createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Matrix4 getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Matrix4>(create);
  static Matrix4? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get values => $_getList(0);
}

/// 与 Matrix4 结构相同，但存储 uint32（用于关节状态码等）。
class Matrix4Int32 extends $pb.GeneratedMessage {
  factory Matrix4Int32({
    $core.Iterable<$core.int>? values,
  }) {
    final result = create();
    if (values != null) result.values.addAll(values);
    return result;
  }

  Matrix4Int32._();

  factory Matrix4Int32.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Matrix4Int32.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Matrix4Int32',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'values', $pb.PbFieldType.KU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Matrix4Int32 clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Matrix4Int32 copyWith(void Function(Matrix4Int32) updates) =>
      super.copyWith((message) => updates(message as Matrix4Int32))
          as Matrix4Int32;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Matrix4Int32 create() => Matrix4Int32._();
  @$core.override
  Matrix4Int32 createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Matrix4Int32 getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Matrix4Int32>(create);
  static Matrix4Int32? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get values => $_getList(0);
}

/// 四元数，用于描述 IMU 姿态。
/// 遵循 Hamilton 约定：q = w + xi + yj + zk。
class Quaternion extends $pb.GeneratedMessage {
  factory Quaternion({
    $core.double? w,
    $core.double? x,
    $core.double? y,
    $core.double? z,
  }) {
    final result = create();
    if (w != null) result.w = w;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (z != null) result.z = z;
    return result;
  }

  Quaternion._();

  factory Quaternion.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Quaternion.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Quaternion',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'w', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'z', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Quaternion clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Quaternion copyWith(void Function(Quaternion) updates) =>
      super.copyWith((message) => updates(message as Quaternion)) as Quaternion;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Quaternion create() => Quaternion._();
  @$core.override
  Quaternion createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Quaternion getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Quaternion>(create);
  static Quaternion? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get w => $_getN(0);
  @$pb.TagNumber(1)
  set w($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasW() => $_has(0);
  @$pb.TagNumber(1)
  void clearW() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get x => $_getN(1);
  @$pb.TagNumber(2)
  set x($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasX() => $_has(1);
  @$pb.TagNumber(2)
  void clearX() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get y => $_getN(2);
  @$pb.TagNumber(3)
  set y($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasY() => $_has(2);
  @$pb.TagNumber(3)
  void clearY() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get z => $_getN(3);
  @$pb.TagNumber(4)
  set z($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasZ() => $_has(3);
  @$pb.TagNumber(4)
  void clearZ() => $_clearField(4);
}

/// 带时间戳的关节目标角度。
class Action extends $pb.GeneratedMessage {
  factory Action({
    Matrix4? data,
    $0.Duration? timestamp,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (timestamp != null) result.timestamp = timestamp;
    return result;
  }

  Action._();

  factory Action.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Action.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Action',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOM<Matrix4>(1, _omitFieldNames ? '' : 'data', subBuilder: Matrix4.create)
    ..aOM<$0.Duration>(2, _omitFieldNames ? '' : 'timestamp',
        subBuilder: $0.Duration.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Action clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Action copyWith(void Function(Action) updates) =>
      super.copyWith((message) => updates(message as Action)) as Action;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Action create() => Action._();
  @$core.override
  Action createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Action getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Action>(create);
  static Action? _defaultInstance;

  /// 目标关节角度 (rad)，16 个关节。
  @$pb.TagNumber(1)
  Matrix4 get data => $_getN(0);
  @$pb.TagNumber(1)
  set data(Matrix4 value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  Matrix4 ensureData() => $_ensure(0);

  /// 相对于会话开始时间的时间戳。
  @$pb.TagNumber(2)
  $0.Duration get timestamp => $_getN(1);
  @$pb.TagNumber(2)
  set timestamp($0.Duration value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Duration ensureTimestamp() => $_ensure(1);
}

/// 机器人模型参数，用于仿真初始化或参数查询。
class RobotModel extends $pb.GeneratedMessage {
  factory RobotModel({
    RobotType? type,
    Matrix4? initialJointPosition,
    Matrix4? initialJointVelocity,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (initialJointPosition != null)
      result.initialJointPosition = initialJointPosition;
    if (initialJointVelocity != null)
      result.initialJointVelocity = initialJointVelocity;
    return result;
  }

  RobotModel._();

  factory RobotModel.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RobotModel.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RobotModel',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aE<RobotType>(1, _omitFieldNames ? '' : 'type',
        enumValues: RobotType.values)
    ..aOM<Matrix4>(2, _omitFieldNames ? '' : 'initialJointPosition',
        subBuilder: Matrix4.create)
    ..aOM<Matrix4>(3, _omitFieldNames ? '' : 'initialJointVelocity',
        subBuilder: Matrix4.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RobotModel clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RobotModel copyWith(void Function(RobotModel) updates) =>
      super.copyWith((message) => updates(message as RobotModel)) as RobotModel;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RobotModel create() => RobotModel._();
  @$core.override
  RobotModel createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RobotModel getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RobotModel>(create);
  static RobotModel? _defaultInstance;

  /// 机器人型号。
  @$pb.TagNumber(1)
  RobotType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(RobotType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  /// 初始关节角度 (rad)。
  @$pb.TagNumber(2)
  Matrix4 get initialJointPosition => $_getN(1);
  @$pb.TagNumber(2)
  set initialJointPosition(Matrix4 value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasInitialJointPosition() => $_has(1);
  @$pb.TagNumber(2)
  void clearInitialJointPosition() => $_clearField(2);
  @$pb.TagNumber(2)
  Matrix4 ensureInitialJointPosition() => $_ensure(1);

  /// 初始关节角速度 (rad/s)，通常为全零。
  @$pb.TagNumber(3)
  Matrix4 get initialJointVelocity => $_getN(2);
  @$pb.TagNumber(3)
  set initialJointVelocity(Matrix4 value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasInitialJointVelocity() => $_has(2);
  @$pb.TagNumber(3)
  void clearInitialJointVelocity() => $_clearField(3);
  @$pb.TagNumber(3)
  Matrix4 ensureInitialJointVelocity() => $_ensure(2);
}

/// 仿真器发送给控制器的传感器状态。
class SimState extends $pb.GeneratedMessage {
  factory SimState({
    Vector3? gyroscope,
    Quaternion? quaternion,
    Matrix4? jointPosition,
    Matrix4? jointVelocity,
    $0.Duration? timestamp,
  }) {
    final result = create();
    if (gyroscope != null) result.gyroscope = gyroscope;
    if (quaternion != null) result.quaternion = quaternion;
    if (jointPosition != null) result.jointPosition = jointPosition;
    if (jointVelocity != null) result.jointVelocity = jointVelocity;
    if (timestamp != null) result.timestamp = timestamp;
    return result;
  }

  SimState._();

  factory SimState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SimState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SimState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOM<Vector3>(1, _omitFieldNames ? '' : 'gyroscope',
        subBuilder: Vector3.create)
    ..aOM<Quaternion>(2, _omitFieldNames ? '' : 'quaternion',
        subBuilder: Quaternion.create)
    ..aOM<Matrix4>(3, _omitFieldNames ? '' : 'jointPosition',
        subBuilder: Matrix4.create)
    ..aOM<Matrix4>(4, _omitFieldNames ? '' : 'jointVelocity',
        subBuilder: Matrix4.create)
    ..aOM<$0.Duration>(5, _omitFieldNames ? '' : 'timestamp',
        subBuilder: $0.Duration.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SimState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SimState copyWith(void Function(SimState) updates) =>
      super.copyWith((message) => updates(message as SimState)) as SimState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SimState create() => SimState._();
  @$core.override
  SimState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SimState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SimState>(create);
  static SimState? _defaultInstance;

  /// IMU 角速度 (rad/s)，body frame。
  @$pb.TagNumber(1)
  Vector3 get gyroscope => $_getN(0);
  @$pb.TagNumber(1)
  set gyroscope(Vector3 value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasGyroscope() => $_has(0);
  @$pb.TagNumber(1)
  void clearGyroscope() => $_clearField(1);
  @$pb.TagNumber(1)
  Vector3 ensureGyroscope() => $_ensure(0);

  /// IMU 四元数姿态（world → body 旋转）。
  @$pb.TagNumber(2)
  Quaternion get quaternion => $_getN(1);
  @$pb.TagNumber(2)
  set quaternion(Quaternion value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasQuaternion() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuaternion() => $_clearField(2);
  @$pb.TagNumber(2)
  Quaternion ensureQuaternion() => $_ensure(1);

  /// 当前关节角度 (rad)。
  @$pb.TagNumber(3)
  Matrix4 get jointPosition => $_getN(2);
  @$pb.TagNumber(3)
  set jointPosition(Matrix4 value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasJointPosition() => $_has(2);
  @$pb.TagNumber(3)
  void clearJointPosition() => $_clearField(3);
  @$pb.TagNumber(3)
  Matrix4 ensureJointPosition() => $_ensure(2);

  /// 当前关节角速度 (rad/s)。
  @$pb.TagNumber(4)
  Matrix4 get jointVelocity => $_getN(3);
  @$pb.TagNumber(4)
  set jointVelocity(Matrix4 value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasJointVelocity() => $_has(3);
  @$pb.TagNumber(4)
  void clearJointVelocity() => $_clearField(4);
  @$pb.TagNumber(4)
  Matrix4 ensureJointVelocity() => $_ensure(3);

  /// 仿真时间戳。
  @$pb.TagNumber(5)
  $0.Duration get timestamp => $_getN(4);
  @$pb.TagNumber(5)
  set timestamp($0.Duration value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasTimestamp() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestamp() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.Duration ensureTimestamp() => $_ensure(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
