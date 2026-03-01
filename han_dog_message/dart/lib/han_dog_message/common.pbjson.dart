// This is a generated file - do not edit.
//
// Generated from han_dog_message/common.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use robotTypeDescriptor instead')
const RobotType$json = {
  '1': 'RobotType',
  '2': [
    {'1': 'SKINNY', '2': 0},
    {'1': 'HAN', '2': 1},
    {'1': 'MINI', '2': 2},
    {'1': 'MINI2', '2': 3},
  ],
};

/// Descriptor for `RobotType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List robotTypeDescriptor = $convert.base64Decode(
    'CglSb2JvdFR5cGUSCgoGU0tJTk5ZEAASBwoDSEFOEAESCAoETUlOSRACEgkKBU1JTkkyEAM=');

@$core.Deprecated('Use vector3Descriptor instead')
const Vector3$json = {
  '1': 'Vector3',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 2, '10': 'y'},
    {'1': 'z', '3': 3, '4': 1, '5': 2, '10': 'z'},
  ],
};

/// Descriptor for `Vector3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vector3Descriptor = $convert.base64Decode(
    'CgdWZWN0b3IzEgwKAXgYASABKAJSAXgSDAoBeRgCIAEoAlIBeRIMCgF6GAMgASgCUgF6');

@$core.Deprecated('Use arrayFloatDescriptor instead')
const ArrayFloat$json = {
  '1': 'ArrayFloat',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 2, '10': 'values'},
  ],
};

/// Descriptor for `ArrayFloat`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List arrayFloatDescriptor =
    $convert.base64Decode('CgpBcnJheUZsb2F0EhYKBnZhbHVlcxgBIAMoAlIGdmFsdWVz');

@$core.Deprecated('Use matrix4Descriptor instead')
const Matrix4$json = {
  '1': 'Matrix4',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 2, '10': 'values'},
  ],
};

/// Descriptor for `Matrix4`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List matrix4Descriptor =
    $convert.base64Decode('CgdNYXRyaXg0EhYKBnZhbHVlcxgBIAMoAlIGdmFsdWVz');

@$core.Deprecated('Use matrix4Int32Descriptor instead')
const Matrix4Int32$json = {
  '1': 'Matrix4Int32',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 13, '10': 'values'},
  ],
};

/// Descriptor for `Matrix4Int32`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List matrix4Int32Descriptor = $convert
    .base64Decode('CgxNYXRyaXg0SW50MzISFgoGdmFsdWVzGAEgAygNUgZ2YWx1ZXM=');

@$core.Deprecated('Use quaternionDescriptor instead')
const Quaternion$json = {
  '1': 'Quaternion',
  '2': [
    {'1': 'w', '3': 1, '4': 1, '5': 2, '10': 'w'},
    {'1': 'x', '3': 2, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 3, '4': 1, '5': 2, '10': 'y'},
    {'1': 'z', '3': 4, '4': 1, '5': 2, '10': 'z'},
  ],
};

/// Descriptor for `Quaternion`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List quaternionDescriptor = $convert.base64Decode(
    'CgpRdWF0ZXJuaW9uEgwKAXcYASABKAJSAXcSDAoBeBgCIAEoAlIBeBIMCgF5GAMgASgCUgF5Eg'
    'wKAXoYBCABKAJSAXo=');

@$core.Deprecated('Use actionDescriptor instead')
const Action$json = {
  '1': 'Action',
  '2': [
    {
      '1': 'data',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'data'
    },
    {
      '1': 'timestamp',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Duration',
      '10': 'timestamp'
    },
  ],
};

/// Descriptor for `Action`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List actionDescriptor = $convert.base64Decode(
    'CgZBY3Rpb24SJAoEZGF0YRgBIAEoCzIQLmhhbl9kb2cuTWF0cml4NFIEZGF0YRI3Cgl0aW1lc3'
    'RhbXAYAiABKAsyGS5nb29nbGUucHJvdG9idWYuRHVyYXRpb25SCXRpbWVzdGFtcA==');

@$core.Deprecated('Use robotModelDescriptor instead')
const RobotModel$json = {
  '1': 'RobotModel',
  '2': [
    {
      '1': 'type',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.han_dog.RobotType',
      '10': 'type'
    },
    {
      '1': 'initial_joint_position',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'initialJointPosition'
    },
    {
      '1': 'initial_joint_velocity',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'initialJointVelocity'
    },
  ],
};

/// Descriptor for `RobotModel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List robotModelDescriptor = $convert.base64Decode(
    'CgpSb2JvdE1vZGVsEiYKBHR5cGUYASABKA4yEi5oYW5fZG9nLlJvYm90VHlwZVIEdHlwZRJGCh'
    'Zpbml0aWFsX2pvaW50X3Bvc2l0aW9uGAIgASgLMhAuaGFuX2RvZy5NYXRyaXg0UhRpbml0aWFs'
    'Sm9pbnRQb3NpdGlvbhJGChZpbml0aWFsX2pvaW50X3ZlbG9jaXR5GAMgASgLMhAuaGFuX2RvZy'
    '5NYXRyaXg0UhRpbml0aWFsSm9pbnRWZWxvY2l0eQ==');

@$core.Deprecated('Use simStateDescriptor instead')
const SimState$json = {
  '1': 'SimState',
  '2': [
    {
      '1': 'gyroscope',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Vector3',
      '10': 'gyroscope'
    },
    {
      '1': 'quaternion',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Quaternion',
      '10': 'quaternion'
    },
    {
      '1': 'joint_position',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'jointPosition'
    },
    {
      '1': 'joint_velocity',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'jointVelocity'
    },
    {
      '1': 'timestamp',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Duration',
      '10': 'timestamp'
    },
  ],
};

/// Descriptor for `SimState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List simStateDescriptor = $convert.base64Decode(
    'CghTaW1TdGF0ZRIuCglneXJvc2NvcGUYASABKAsyEC5oYW5fZG9nLlZlY3RvcjNSCWd5cm9zY2'
    '9wZRIzCgpxdWF0ZXJuaW9uGAIgASgLMhMuaGFuX2RvZy5RdWF0ZXJuaW9uUgpxdWF0ZXJuaW9u'
    'EjcKDmpvaW50X3Bvc2l0aW9uGAMgASgLMhAuaGFuX2RvZy5NYXRyaXg0Ug1qb2ludFBvc2l0aW'
    '9uEjcKDmpvaW50X3ZlbG9jaXR5GAQgASgLMhAuaGFuX2RvZy5NYXRyaXg0Ug1qb2ludFZlbG9j'
    'aXR5EjcKCXRpbWVzdGFtcBgFIAEoCzIZLmdvb2dsZS5wcm90b2J1Zi5EdXJhdGlvblIJdGltZX'
    'N0YW1w');
