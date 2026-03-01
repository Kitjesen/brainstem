// This is a generated file - do not edit.
//
// Generated from han_dog_message/cms.proto.

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

@$core.Deprecated('Use historyDescriptor instead')
const History$json = {
  '1': 'History',
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
      '1': 'projected_gravity',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Vector3',
      '10': 'projectedGravity'
    },
    {
      '1': 'command',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Command',
      '10': 'command'
    },
    {
      '1': 'joint_position',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'jointPosition'
    },
    {
      '1': 'joint_velocity',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'jointVelocity'
    },
    {
      '1': 'action',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'action'
    },
    {
      '1': 'next_action',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'nextAction'
    },
    {
      '1': 'timestamp',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Duration',
      '10': 'timestamp'
    },
    {'1': 'kp', '3': 9, '4': 1, '5': 11, '6': '.han_dog.Matrix4', '10': 'kp'},
    {'1': 'kd', '3': 10, '4': 1, '5': 11, '6': '.han_dog.Matrix4', '10': 'kd'},
  ],
};

/// Descriptor for `History`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List historyDescriptor = $convert.base64Decode(
    'CgdIaXN0b3J5Ei4KCWd5cm9zY29wZRgBIAEoCzIQLmhhbl9kb2cuVmVjdG9yM1IJZ3lyb3Njb3'
    'BlEj0KEXByb2plY3RlZF9ncmF2aXR5GAIgASgLMhAuaGFuX2RvZy5WZWN0b3IzUhBwcm9qZWN0'
    'ZWRHcmF2aXR5EioKB2NvbW1hbmQYAyABKAsyEC5oYW5fZG9nLkNvbW1hbmRSB2NvbW1hbmQSNw'
    'oOam9pbnRfcG9zaXRpb24YBCABKAsyEC5oYW5fZG9nLk1hdHJpeDRSDWpvaW50UG9zaXRpb24S'
    'NwoOam9pbnRfdmVsb2NpdHkYBSABKAsyEC5oYW5fZG9nLk1hdHJpeDRSDWpvaW50VmVsb2NpdH'
    'kSKAoGYWN0aW9uGAYgASgLMhAuaGFuX2RvZy5NYXRyaXg0UgZhY3Rpb24SMQoLbmV4dF9hY3Rp'
    'b24YByABKAsyEC5oYW5fZG9nLk1hdHJpeDRSCm5leHRBY3Rpb24SNwoJdGltZXN0YW1wGAggAS'
    'gLMhkuZ29vZ2xlLnByb3RvYnVmLkR1cmF0aW9uUgl0aW1lc3RhbXASIAoCa3AYCSABKAsyEC5o'
    'YW5fZG9nLk1hdHJpeDRSAmtwEiAKAmtkGAogASgLMhAuaGFuX2RvZy5NYXRyaXg0UgJrZA==');

@$core.Deprecated('Use imuDescriptor instead')
const Imu$json = {
  '1': 'Imu',
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
      '1': 'timestamp',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Duration',
      '10': 'timestamp'
    },
  ],
};

/// Descriptor for `Imu`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imuDescriptor = $convert.base64Decode(
    'CgNJbXUSLgoJZ3lyb3Njb3BlGAEgASgLMhAuaGFuX2RvZy5WZWN0b3IzUglneXJvc2NvcGUSMw'
    'oKcXVhdGVybmlvbhgCIAEoCzITLmhhbl9kb2cuUXVhdGVybmlvblIKcXVhdGVybmlvbhI3Cgl0'
    'aW1lc3RhbXAYAyABKAsyGS5nb29nbGUucHJvdG9idWYuRHVyYXRpb25SCXRpbWVzdGFtcA==');

@$core.Deprecated('Use jointDescriptor instead')
const Joint$json = {
  '1': 'Joint',
  '2': [
    {
      '1': 'single_joint',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.han_dog.SingleJoint',
      '9': 0,
      '10': 'singleJoint'
    },
    {
      '1': 'all_joints',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.han_dog.AllJoints',
      '9': 0,
      '10': 'allJoints'
    },
    {
      '1': 'timestamp',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Duration',
      '10': 'timestamp'
    },
  ],
  '8': [
    {'1': 'data'},
  ],
};

/// Descriptor for `Joint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jointDescriptor = $convert.base64Decode(
    'CgVKb2ludBI5CgxzaW5nbGVfam9pbnQYASABKAsyFC5oYW5fZG9nLlNpbmdsZUpvaW50SABSC3'
    'NpbmdsZUpvaW50EjMKCmFsbF9qb2ludHMYAiABKAsyEi5oYW5fZG9nLkFsbEpvaW50c0gAUglh'
    'bGxKb2ludHMSNwoJdGltZXN0YW1wGAMgASgLMhkuZ29vZ2xlLnByb3RvYnVmLkR1cmF0aW9uUg'
    'l0aW1lc3RhbXBCBgoEZGF0YQ==');

@$core.Deprecated('Use singleJointDescriptor instead')
const SingleJoint$json = {
  '1': 'SingleJoint',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 13, '10': 'id'},
    {'1': 'position', '3': 2, '4': 1, '5': 2, '10': 'position'},
    {'1': 'velocity', '3': 3, '4': 1, '5': 2, '10': 'velocity'},
    {'1': 'torque', '3': 4, '4': 1, '5': 2, '10': 'torque'},
    {'1': 'status', '3': 5, '4': 1, '5': 13, '10': 'status'},
  ],
};

/// Descriptor for `SingleJoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List singleJointDescriptor = $convert.base64Decode(
    'CgtTaW5nbGVKb2ludBIOCgJpZBgBIAEoDVICaWQSGgoIcG9zaXRpb24YAiABKAJSCHBvc2l0aW'
    '9uEhoKCHZlbG9jaXR5GAMgASgCUgh2ZWxvY2l0eRIWCgZ0b3JxdWUYBCABKAJSBnRvcnF1ZRIW'
    'CgZzdGF0dXMYBSABKA1SBnN0YXR1cw==');

@$core.Deprecated('Use allJointsDescriptor instead')
const AllJoints$json = {
  '1': 'AllJoints',
  '2': [
    {
      '1': 'position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'position'
    },
    {
      '1': 'velocity',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'velocity'
    },
    {
      '1': 'torque',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4',
      '10': 'torque'
    },
    {
      '1': 'status',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Matrix4Int32',
      '10': 'status'
    },
  ],
};

/// Descriptor for `AllJoints`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List allJointsDescriptor = $convert.base64Decode(
    'CglBbGxKb2ludHMSLAoIcG9zaXRpb24YASABKAsyEC5oYW5fZG9nLk1hdHJpeDRSCHBvc2l0aW'
    '9uEiwKCHZlbG9jaXR5GAIgASgLMhAuaGFuX2RvZy5NYXRyaXg0Ugh2ZWxvY2l0eRIoCgZ0b3Jx'
    'dWUYAyABKAsyEC5oYW5fZG9nLk1hdHJpeDRSBnRvcnF1ZRItCgZzdGF0dXMYBCABKAsyFS5oYW'
    '5fZG9nLk1hdHJpeDRJbnQzMlIGc3RhdHVz');

@$core.Deprecated('Use paramsDescriptor instead')
const Params$json = {
  '1': 'Params',
  '2': [
    {
      '1': 'robot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.han_dog.RobotModel',
      '10': 'robot'
    },
  ],
};

/// Descriptor for `Params`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List paramsDescriptor = $convert.base64Decode(
    'CgZQYXJhbXMSKQoFcm9ib3QYASABKAsyEy5oYW5fZG9nLlJvYm90TW9kZWxSBXJvYm90');

@$core.Deprecated('Use profileRequestDescriptor instead')
const ProfileRequest$json = {
  '1': 'ProfileRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `ProfileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List profileRequestDescriptor =
    $convert.base64Decode('Cg5Qcm9maWxlUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1l');

@$core.Deprecated('Use profileInfoDescriptor instead')
const ProfileInfo$json = {
  '1': 'ProfileInfo',
  '2': [
    {'1': 'current', '3': 1, '4': 1, '5': 9, '10': 'current'},
    {'1': 'available', '3': 2, '4': 3, '5': 9, '10': 'available'},
    {'1': 'descriptions', '3': 3, '4': 3, '5': 9, '10': 'descriptions'},
    {
      '1': 'current_description',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'currentDescription'
    },
  ],
};

/// Descriptor for `ProfileInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List profileInfoDescriptor = $convert.base64Decode(
    'CgtQcm9maWxlSW5mbxIYCgdjdXJyZW50GAEgASgJUgdjdXJyZW50EhwKCWF2YWlsYWJsZRgCIA'
    'MoCVIJYXZhaWxhYmxlEiIKDGRlc2NyaXB0aW9ucxgDIAMoCVIMZGVzY3JpcHRpb25zEi8KE2N1'
    'cnJlbnRfZGVzY3JpcHRpb24YBCABKAlSEmN1cnJlbnREZXNjcmlwdGlvbg==');

@$core.Deprecated('Use commandDescriptor instead')
const Command$json = {
  '1': 'Command',
  '2': [
    {
      '1': 'idle',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Empty',
      '9': 0,
      '10': 'idle'
    },
    {
      '1': 'stand_up',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Empty',
      '9': 0,
      '10': 'standUp'
    },
    {
      '1': 'sit_down',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Empty',
      '9': 0,
      '10': 'sitDown'
    },
    {
      '1': 'walk',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.han_dog.Vector3',
      '9': 0,
      '10': 'walk'
    },
  ],
  '8': [
    {'1': 'data'},
  ],
};

/// Descriptor for `Command`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandDescriptor = $convert.base64Decode(
    'CgdDb21tYW5kEiwKBGlkbGUYASABKAsyFi5nb29nbGUucHJvdG9idWYuRW1wdHlIAFIEaWRsZR'
    'IzCghzdGFuZF91cBgCIAEoCzIWLmdvb2dsZS5wcm90b2J1Zi5FbXB0eUgAUgdzdGFuZFVwEjMK'
    'CHNpdF9kb3duGAMgASgLMhYuZ29vZ2xlLnByb3RvYnVmLkVtcHR5SABSB3NpdERvd24SJgoEd2'
    'FsaxgEIAEoCzIQLmhhbl9kb2cuVmVjdG9yM0gAUgR3YWxrQgYKBGRhdGE=');
