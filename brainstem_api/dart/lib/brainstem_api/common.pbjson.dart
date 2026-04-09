// This is a generated file - do not edit.
//
// Generated from brainstem_api/common.proto.

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
    {'1': 'x', '3': 1, '4': 1, '5': 1, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 1, '10': 'y'},
    {'1': 'z', '3': 3, '4': 1, '5': 1, '10': 'z'},
  ],
};

/// Descriptor for `Vector3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vector3Descriptor = $convert.base64Decode(
    'CgdWZWN0b3IzEgwKAXgYASABKAFSAXgSDAoBeRgCIAEoAVIBeRIMCgF6GAMgASgBUgF6');

@$core.Deprecated('Use arrayFloatDescriptor instead')
const ArrayFloat$json = {
  '1': 'ArrayFloat',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 1, '10': 'values'},
  ],
};

/// Descriptor for `ArrayFloat`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List arrayFloatDescriptor =
    $convert.base64Decode('CgpBcnJheUZsb2F0EhYKBnZhbHVlcxgBIAMoAVIGdmFsdWVz');

@$core.Deprecated('Use matrix4Descriptor instead')
const Matrix4$json = {
  '1': 'Matrix4',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 1, '10': 'values'},
  ],
};

/// Descriptor for `Matrix4`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List matrix4Descriptor =
    $convert.base64Decode('CgdNYXRyaXg0EhYKBnZhbHVlcxgBIAMoAVIGdmFsdWVz');

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
    {'1': 'w', '3': 1, '4': 1, '5': 1, '10': 'w'},
    {'1': 'x', '3': 2, '4': 1, '5': 1, '10': 'x'},
    {'1': 'y', '3': 3, '4': 1, '5': 1, '10': 'y'},
    {'1': 'z', '3': 4, '4': 1, '5': 1, '10': 'z'},
  ],
};

/// Descriptor for `Quaternion`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List quaternionDescriptor = $convert.base64Decode(
    'CgpRdWF0ZXJuaW9uEgwKAXcYASABKAFSAXcSDAoBeBgCIAEoAVIBeBIMCgF5GAMgASgBUgF5Eg'
    'wKAXoYBCABKAFSAXo=');

@$core.Deprecated('Use actionDescriptor instead')
const Action$json = {
  '1': 'Action',
  '2': [
    {
      '1': 'data',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
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
    'CgZBY3Rpb24SLQoEZGF0YRgBIAEoCzIZLmJyYWluc3RlbS5hcGkudjEuTWF0cml4NFIEZGF0YR'
    'I3Cgl0aW1lc3RhbXAYAiABKAsyGS5nb29nbGUucHJvdG9idWYuRHVyYXRpb25SCXRpbWVzdGFt'
    'cA==');

@$core.Deprecated('Use robotModelDescriptor instead')
const RobotModel$json = {
  '1': 'RobotModel',
  '2': [
    {
      '1': 'type',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.brainstem.api.v1.RobotType',
      '10': 'type'
    },
    {
      '1': 'initial_joint_position',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'initialJointPosition'
    },
    {
      '1': 'initial_joint_velocity',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'initialJointVelocity'
    },
  ],
};

/// Descriptor for `RobotModel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List robotModelDescriptor = $convert.base64Decode(
    'CgpSb2JvdE1vZGVsEi8KBHR5cGUYASABKA4yGy5icmFpbnN0ZW0uYXBpLnYxLlJvYm90VHlwZV'
    'IEdHlwZRJPChZpbml0aWFsX2pvaW50X3Bvc2l0aW9uGAIgASgLMhkuYnJhaW5zdGVtLmFwaS52'
    'MS5NYXRyaXg0UhRpbml0aWFsSm9pbnRQb3NpdGlvbhJPChZpbml0aWFsX2pvaW50X3ZlbG9jaX'
    'R5GAMgASgLMhkuYnJhaW5zdGVtLmFwaS52MS5NYXRyaXg0UhRpbml0aWFsSm9pbnRWZWxvY2l0'
    'eQ==');

@$core.Deprecated('Use simStateDescriptor instead')
const SimState$json = {
  '1': 'SimState',
  '2': [
    {
      '1': 'gyroscope',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Vector3',
      '10': 'gyroscope'
    },
    {
      '1': 'quaternion',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Quaternion',
      '10': 'quaternion'
    },
    {
      '1': 'joint_position',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'jointPosition'
    },
    {
      '1': 'joint_velocity',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
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
    'CghTaW1TdGF0ZRI3CglneXJvc2NvcGUYASABKAsyGS5icmFpbnN0ZW0uYXBpLnYxLlZlY3Rvcj'
    'NSCWd5cm9zY29wZRI8CgpxdWF0ZXJuaW9uGAIgASgLMhwuYnJhaW5zdGVtLmFwaS52MS5RdWF0'
    'ZXJuaW9uUgpxdWF0ZXJuaW9uEkAKDmpvaW50X3Bvc2l0aW9uGAMgASgLMhkuYnJhaW5zdGVtLm'
    'FwaS52MS5NYXRyaXg0Ug1qb2ludFBvc2l0aW9uEkAKDmpvaW50X3ZlbG9jaXR5GAQgASgLMhku'
    'YnJhaW5zdGVtLmFwaS52MS5NYXRyaXg0Ug1qb2ludFZlbG9jaXR5EjcKCXRpbWVzdGFtcBgFIA'
    'EoCzIZLmdvb2dsZS5wcm90b2J1Zi5EdXJhdGlvblIJdGltZXN0YW1w');
