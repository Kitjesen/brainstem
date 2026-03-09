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

/// 运动指令。
class CmsStateKind extends $pb.ProtobufEnum {
  static const CmsStateKind CMS_STATE_KIND_ZERO =
      CmsStateKind._(0, _omitEnumNames ? '' : 'CMS_STATE_KIND_ZERO');
  static const CmsStateKind CMS_STATE_KIND_GROUNDED =
      CmsStateKind._(1, _omitEnumNames ? '' : 'CMS_STATE_KIND_GROUNDED');
  static const CmsStateKind CMS_STATE_KIND_STANDING =
      CmsStateKind._(2, _omitEnumNames ? '' : 'CMS_STATE_KIND_STANDING');
  static const CmsStateKind CMS_STATE_KIND_WALKING =
      CmsStateKind._(3, _omitEnumNames ? '' : 'CMS_STATE_KIND_WALKING');
  static const CmsStateKind CMS_STATE_KIND_TRANSITIONING =
      CmsStateKind._(4, _omitEnumNames ? '' : 'CMS_STATE_KIND_TRANSITIONING');

  static const $core.List<CmsStateKind> values = <CmsStateKind>[
    CMS_STATE_KIND_ZERO,
    CMS_STATE_KIND_GROUNDED,
    CMS_STATE_KIND_STANDING,
    CMS_STATE_KIND_WALKING,
    CMS_STATE_KIND_TRANSITIONING,
  ];

  static final $core.List<CmsStateKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static CmsStateKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CmsStateKind._(super.value, super.name);
}

class CmsTransitionKind extends $pb.ProtobufEnum {
  static const CmsTransitionKind CMS_TRANSITION_KIND_NONE =
      CmsTransitionKind._(0, _omitEnumNames ? '' : 'CMS_TRANSITION_KIND_NONE');
  static const CmsTransitionKind CMS_TRANSITION_KIND_STAND_UP =
      CmsTransitionKind._(
          1, _omitEnumNames ? '' : 'CMS_TRANSITION_KIND_STAND_UP');
  static const CmsTransitionKind CMS_TRANSITION_KIND_SIT_DOWN =
      CmsTransitionKind._(
          2, _omitEnumNames ? '' : 'CMS_TRANSITION_KIND_SIT_DOWN');
  static const CmsTransitionKind CMS_TRANSITION_KIND_GESTURE =
      CmsTransitionKind._(
          3, _omitEnumNames ? '' : 'CMS_TRANSITION_KIND_GESTURE');

  static const $core.List<CmsTransitionKind> values = <CmsTransitionKind>[
    CMS_TRANSITION_KIND_NONE,
    CMS_TRANSITION_KIND_STAND_UP,
    CMS_TRANSITION_KIND_SIT_DOWN,
    CMS_TRANSITION_KIND_GESTURE,
  ];

  static final $core.List<CmsTransitionKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static CmsTransitionKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CmsTransitionKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
