// This is a generated file - do not edit.
//
// Generated from han_dog_message/mujoco.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as $3;

import 'common.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// MuJoCo viewer 的一帧数据。
class ViewerFrame extends $pb.GeneratedMessage {
  factory ViewerFrame({
    $0.ArrayFloat? qpos,
    $0.ArrayFloat? qvel,
    $3.Duration? timestamp,
  }) {
    final result = create();
    if (qpos != null) result.qpos = qpos;
    if (qvel != null) result.qvel = qvel;
    if (timestamp != null) result.timestamp = timestamp;
    return result;
  }

  ViewerFrame._();

  factory ViewerFrame.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ViewerFrame.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ViewerFrame',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'han_dog'),
      createEmptyInstance: create)
    ..aOM<$0.ArrayFloat>(1, _omitFieldNames ? '' : 'qpos',
        subBuilder: $0.ArrayFloat.create)
    ..aOM<$0.ArrayFloat>(2, _omitFieldNames ? '' : 'qvel',
        subBuilder: $0.ArrayFloat.create)
    ..aOM<$3.Duration>(3, _omitFieldNames ? '' : 'timestamp',
        subBuilder: $3.Duration.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ViewerFrame clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ViewerFrame copyWith(void Function(ViewerFrame) updates) =>
      super.copyWith((message) => updates(message as ViewerFrame))
          as ViewerFrame;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ViewerFrame create() => ViewerFrame._();
  @$core.override
  ViewerFrame createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ViewerFrame getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ViewerFrame>(create);
  static ViewerFrame? _defaultInstance;

  /// 广义坐标 (qpos)：MuJoCo 模型的位置/姿态状态。
  @$pb.TagNumber(1)
  $0.ArrayFloat get qpos => $_getN(0);
  @$pb.TagNumber(1)
  set qpos($0.ArrayFloat value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasQpos() => $_has(0);
  @$pb.TagNumber(1)
  void clearQpos() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.ArrayFloat ensureQpos() => $_ensure(0);

  /// 广义速度 (qvel)：MuJoCo 模型的速度状态。
  @$pb.TagNumber(2)
  $0.ArrayFloat get qvel => $_getN(1);
  @$pb.TagNumber(2)
  set qvel($0.ArrayFloat value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasQvel() => $_has(1);
  @$pb.TagNumber(2)
  void clearQvel() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.ArrayFloat ensureQvel() => $_ensure(1);

  /// 相对于会话开始时间的时间戳。
  @$pb.TagNumber(3)
  $3.Duration get timestamp => $_getN(2);
  @$pb.TagNumber(3)
  set timestamp($3.Duration value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestamp() => $_clearField(3);
  @$pb.TagNumber(3)
  $3.Duration ensureTimestamp() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
