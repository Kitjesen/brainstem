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

/// 机器人型号枚举。
class RobotType extends $pb.ProtobufEnum {
  static const RobotType SKINNY =
      RobotType._(0, _omitEnumNames ? '' : 'SKINNY');
  static const RobotType HAN = RobotType._(1, _omitEnumNames ? '' : 'HAN');
  static const RobotType MINI = RobotType._(2, _omitEnumNames ? '' : 'MINI');
  static const RobotType MINI2 = RobotType._(3, _omitEnumNames ? '' : 'MINI2');

  static const $core.List<RobotType> values = <RobotType>[
    SKINNY,
    HAN,
    MINI,
    MINI2,
  ];

  static final $core.List<RobotType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static RobotType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RobotType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
