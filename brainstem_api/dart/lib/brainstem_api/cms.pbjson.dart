// This is a generated file - do not edit.
//
// Generated from brainstem_api/cms.proto.

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

@$core.Deprecated('Use cmsStateKindDescriptor instead')
const CmsStateKind$json = {
  '1': 'CmsStateKind',
  '2': [
    {'1': 'CMS_STATE_KIND_ZERO', '2': 0},
    {'1': 'CMS_STATE_KIND_GROUNDED', '2': 1},
    {'1': 'CMS_STATE_KIND_STANDING', '2': 2},
    {'1': 'CMS_STATE_KIND_WALKING', '2': 3},
    {'1': 'CMS_STATE_KIND_TRANSITIONING', '2': 4},
  ],
};

/// Descriptor for `CmsStateKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List cmsStateKindDescriptor = $convert.base64Decode(
    'CgxDbXNTdGF0ZUtpbmQSFwoTQ01TX1NUQVRFX0tJTkRfWkVSTxAAEhsKF0NNU19TVEFURV9LSU'
    '5EX0dST1VOREVEEAESGwoXQ01TX1NUQVRFX0tJTkRfU1RBTkRJTkcQAhIaChZDTVNfU1RBVEVf'
    'S0lORF9XQUxLSU5HEAMSIAocQ01TX1NUQVRFX0tJTkRfVFJBTlNJVElPTklORxAE');

@$core.Deprecated('Use cmsTransitionKindDescriptor instead')
const CmsTransitionKind$json = {
  '1': 'CmsTransitionKind',
  '2': [
    {'1': 'CMS_TRANSITION_KIND_NONE', '2': 0},
    {'1': 'CMS_TRANSITION_KIND_STAND_UP', '2': 1},
    {'1': 'CMS_TRANSITION_KIND_SIT_DOWN', '2': 2},
    {'1': 'CMS_TRANSITION_KIND_GESTURE', '2': 3},
  ],
};

/// Descriptor for `CmsTransitionKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List cmsTransitionKindDescriptor = $convert.base64Decode(
    'ChFDbXNUcmFuc2l0aW9uS2luZBIcChhDTVNfVFJBTlNJVElPTl9LSU5EX05PTkUQABIgChxDTV'
    'NfVFJBTlNJVElPTl9LSU5EX1NUQU5EX1VQEAESIAocQ01TX1RSQU5TSVRJT05fS0lORF9TSVRf'
    'RE9XThACEh8KG0NNU19UUkFOU0lUSU9OX0tJTkRfR0VTVFVSRRAD');

@$core.Deprecated('Use speedModeDescriptor instead')
const SpeedMode$json = {
  '1': 'SpeedMode',
  '2': [
    {'1': 'SPEED_MODE_NORMAL', '2': 0},
    {'1': 'SPEED_MODE_HIGH', '2': 1},
  ],
};

/// Descriptor for `SpeedMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List speedModeDescriptor = $convert.base64Decode(
    'CglTcGVlZE1vZGUSFQoRU1BFRURfTU9ERV9OT1JNQUwQABITCg9TUEVFRF9NT0RFX0hJR0gQAQ'
    '==');

@$core.Deprecated('Use voltageDescriptor instead')
const Voltage$json = {
  '1': 'Voltage',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 1, '10': 'values'},
  ],
};

/// Descriptor for `Voltage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voltageDescriptor =
    $convert.base64Decode('CgdWb2x0YWdlEhYKBnZhbHVlcxgBIAMoAVIGdmFsdWVz');

@$core.Deprecated('Use motorStateDescriptor instead')
const MotorState$json = {
  '1': 'MotorState',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 13, '10': 'id'},
    {'1': 'online', '3': 2, '4': 1, '5': 8, '10': 'online'},
    {'1': 'status_code', '3': 3, '4': 1, '5': 13, '10': 'statusCode'},
    {'1': 'temperature', '3': 4, '4': 1, '5': 1, '10': 'temperature'},
    {'1': 'voltage', '3': 5, '4': 1, '5': 1, '10': 'voltage'},
    {'1': 'position', '3': 6, '4': 1, '5': 1, '10': 'position'},
    {'1': 'velocity', '3': 7, '4': 1, '5': 1, '10': 'velocity'},
    {'1': 'torque', '3': 8, '4': 1, '5': 1, '10': 'torque'},
    {'1': 'errors', '3': 9, '4': 3, '5': 13, '10': 'errors'},
  ],
};

/// Descriptor for `MotorState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List motorStateDescriptor = $convert.base64Decode(
    'CgpNb3RvclN0YXRlEg4KAmlkGAEgASgNUgJpZBIWCgZvbmxpbmUYAiABKAhSBm9ubGluZRIfCg'
    'tzdGF0dXNfY29kZRgDIAEoDVIKc3RhdHVzQ29kZRIgCgt0ZW1wZXJhdHVyZRgEIAEoAVILdGVt'
    'cGVyYXR1cmUSGAoHdm9sdGFnZRgFIAEoAVIHdm9sdGFnZRIaCghwb3NpdGlvbhgGIAEoAVIIcG'
    '9zaXRpb24SGgoIdmVsb2NpdHkYByABKAFSCHZlbG9jaXR5EhYKBnRvcnF1ZRgIIAEoAVIGdG9y'
    'cXVlEhYKBmVycm9ycxgJIAMoDVIGZXJyb3Jz');

@$core.Deprecated('Use motorStatusResponseDescriptor instead')
const MotorStatusResponse$json = {
  '1': 'MotorStatusResponse',
  '2': [
    {
      '1': 'motors',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.brainstem.api.v1.MotorState',
      '10': 'motors'
    },
  ],
};

/// Descriptor for `MotorStatusResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List motorStatusResponseDescriptor = $convert.base64Decode(
    'ChNNb3RvclN0YXR1c1Jlc3BvbnNlEjQKBm1vdG9ycxgBIAMoCzIcLmJyYWluc3RlbS5hcGkudj'
    'EuTW90b3JTdGF0ZVIGbW90b3Jz');

@$core.Deprecated('Use clearFaultRequestDescriptor instead')
const ClearFaultRequest$json = {
  '1': 'ClearFaultRequest',
  '2': [
    {'1': 'joint_ids', '3': 1, '4': 3, '5': 13, '10': 'jointIds'},
  ],
};

/// Descriptor for `ClearFaultRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clearFaultRequestDescriptor = $convert.base64Decode(
    'ChFDbGVhckZhdWx0UmVxdWVzdBIbCglqb2ludF9pZHMYASADKA1SCGpvaW50SWRz');

@$core.Deprecated('Use historyDescriptor instead')
const History$json = {
  '1': 'History',
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
      '1': 'projected_gravity',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Vector3',
      '10': 'projectedGravity'
    },
    {
      '1': 'command',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Command',
      '10': 'command'
    },
    {
      '1': 'joint_position',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'jointPosition'
    },
    {
      '1': 'joint_velocity',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'jointVelocity'
    },
    {
      '1': 'action',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'action'
    },
    {
      '1': 'next_action',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
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
    {
      '1': 'kp',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'kp'
    },
    {
      '1': 'kd',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'kd'
    },
    {'1': 'observation', '3': 11, '4': 3, '5': 1, '10': 'observation'},
  ],
};

/// Descriptor for `History`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List historyDescriptor = $convert.base64Decode(
    'CgdIaXN0b3J5EjcKCWd5cm9zY29wZRgBIAEoCzIZLmJyYWluc3RlbS5hcGkudjEuVmVjdG9yM1'
    'IJZ3lyb3Njb3BlEkYKEXByb2plY3RlZF9ncmF2aXR5GAIgASgLMhkuYnJhaW5zdGVtLmFwaS52'
    'MS5WZWN0b3IzUhBwcm9qZWN0ZWRHcmF2aXR5EjMKB2NvbW1hbmQYAyABKAsyGS5icmFpbnN0ZW'
    '0uYXBpLnYxLkNvbW1hbmRSB2NvbW1hbmQSQAoOam9pbnRfcG9zaXRpb24YBCABKAsyGS5icmFp'
    'bnN0ZW0uYXBpLnYxLk1hdHJpeDRSDWpvaW50UG9zaXRpb24SQAoOam9pbnRfdmVsb2NpdHkYBS'
    'ABKAsyGS5icmFpbnN0ZW0uYXBpLnYxLk1hdHJpeDRSDWpvaW50VmVsb2NpdHkSMQoGYWN0aW9u'
    'GAYgASgLMhkuYnJhaW5zdGVtLmFwaS52MS5NYXRyaXg0UgZhY3Rpb24SOgoLbmV4dF9hY3Rpb2'
    '4YByABKAsyGS5icmFpbnN0ZW0uYXBpLnYxLk1hdHJpeDRSCm5leHRBY3Rpb24SNwoJdGltZXN0'
    'YW1wGAggASgLMhkuZ29vZ2xlLnByb3RvYnVmLkR1cmF0aW9uUgl0aW1lc3RhbXASKQoCa3AYCS'
    'ABKAsyGS5icmFpbnN0ZW0uYXBpLnYxLk1hdHJpeDRSAmtwEikKAmtkGAogASgLMhkuYnJhaW5z'
    'dGVtLmFwaS52MS5NYXRyaXg0UgJrZBIgCgtvYnNlcnZhdGlvbhgLIAMoAVILb2JzZXJ2YXRpb2'
    '4=');

@$core.Deprecated('Use imuDescriptor instead')
const Imu$json = {
  '1': 'Imu',
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
    'CgNJbXUSNwoJZ3lyb3Njb3BlGAEgASgLMhkuYnJhaW5zdGVtLmFwaS52MS5WZWN0b3IzUglneX'
    'Jvc2NvcGUSPAoKcXVhdGVybmlvbhgCIAEoCzIcLmJyYWluc3RlbS5hcGkudjEuUXVhdGVybmlv'
    'blIKcXVhdGVybmlvbhI3Cgl0aW1lc3RhbXAYAyABKAsyGS5nb29nbGUucHJvdG9idWYuRHVyYX'
    'Rpb25SCXRpbWVzdGFtcA==');

@$core.Deprecated('Use jointDescriptor instead')
const Joint$json = {
  '1': 'Joint',
  '2': [
    {
      '1': 'single_joint',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.SingleJoint',
      '9': 0,
      '10': 'singleJoint'
    },
    {
      '1': 'all_joints',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.AllJoints',
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
    'CgVKb2ludBJCCgxzaW5nbGVfam9pbnQYASABKAsyHS5icmFpbnN0ZW0uYXBpLnYxLlNpbmdsZU'
    'pvaW50SABSC3NpbmdsZUpvaW50EjwKCmFsbF9qb2ludHMYAiABKAsyGy5icmFpbnN0ZW0uYXBp'
    'LnYxLkFsbEpvaW50c0gAUglhbGxKb2ludHMSNwoJdGltZXN0YW1wGAMgASgLMhkuZ29vZ2xlLn'
    'Byb3RvYnVmLkR1cmF0aW9uUgl0aW1lc3RhbXBCBgoEZGF0YQ==');

@$core.Deprecated('Use singleJointDescriptor instead')
const SingleJoint$json = {
  '1': 'SingleJoint',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 13, '10': 'id'},
    {'1': 'position', '3': 2, '4': 1, '5': 1, '10': 'position'},
    {'1': 'velocity', '3': 3, '4': 1, '5': 1, '10': 'velocity'},
    {'1': 'torque', '3': 4, '4': 1, '5': 1, '10': 'torque'},
    {'1': 'status', '3': 5, '4': 1, '5': 13, '10': 'status'},
  ],
};

/// Descriptor for `SingleJoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List singleJointDescriptor = $convert.base64Decode(
    'CgtTaW5nbGVKb2ludBIOCgJpZBgBIAEoDVICaWQSGgoIcG9zaXRpb24YAiABKAFSCHBvc2l0aW'
    '9uEhoKCHZlbG9jaXR5GAMgASgBUgh2ZWxvY2l0eRIWCgZ0b3JxdWUYBCABKAFSBnRvcnF1ZRIW'
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
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'position'
    },
    {
      '1': 'velocity',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'velocity'
    },
    {
      '1': 'torque',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4',
      '10': 'torque'
    },
    {
      '1': 'status',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.Matrix4Int32',
      '10': 'status'
    },
  ],
};

/// Descriptor for `AllJoints`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List allJointsDescriptor = $convert.base64Decode(
    'CglBbGxKb2ludHMSNQoIcG9zaXRpb24YASABKAsyGS5icmFpbnN0ZW0uYXBpLnYxLk1hdHJpeD'
    'RSCHBvc2l0aW9uEjUKCHZlbG9jaXR5GAIgASgLMhkuYnJhaW5zdGVtLmFwaS52MS5NYXRyaXg0'
    'Ugh2ZWxvY2l0eRIxCgZ0b3JxdWUYAyABKAsyGS5icmFpbnN0ZW0uYXBpLnYxLk1hdHJpeDRSBn'
    'RvcnF1ZRI2CgZzdGF0dXMYBCABKAsyHi5icmFpbnN0ZW0uYXBpLnYxLk1hdHJpeDRJbnQzMlIG'
    'c3RhdHVz');

@$core.Deprecated('Use paramsDescriptor instead')
const Params$json = {
  '1': 'Params',
  '2': [
    {
      '1': 'robot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.RobotModel',
      '10': 'robot'
    },
  ],
};

/// Descriptor for `Params`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List paramsDescriptor = $convert.base64Decode(
    'CgZQYXJhbXMSMgoFcm9ib3QYASABKAsyHC5icmFpbnN0ZW0uYXBpLnYxLlJvYm90TW9kZWxSBX'
    'JvYm90');

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

@$core.Deprecated('Use cmsStateDescriptor instead')
const CmsState$json = {
  '1': 'CmsState',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.brainstem.api.v1.CmsStateKind',
      '10': 'kind'
    },
    {
      '1': 'transition',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.brainstem.api.v1.CmsTransitionKind',
      '10': 'transition'
    },
    {'1': 'gesture_name', '3': 3, '4': 1, '5': 9, '10': 'gestureName'},
  ],
};

/// Descriptor for `CmsState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cmsStateDescriptor = $convert.base64Decode(
    'CghDbXNTdGF0ZRIyCgRraW5kGAEgASgOMh4uYnJhaW5zdGVtLmFwaS52MS5DbXNTdGF0ZUtpbm'
    'RSBGtpbmQSQwoKdHJhbnNpdGlvbhgCIAEoDjIjLmJyYWluc3RlbS5hcGkudjEuQ21zVHJhbnNp'
    'dGlvbktpbmRSCnRyYW5zaXRpb24SIQoMZ2VzdHVyZV9uYW1lGAMgASgJUgtnZXN0dXJlTmFtZQ'
    '==');

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
      '6': '.brainstem.api.v1.Vector3',
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
    'CHNpdF9kb3duGAMgASgLMhYuZ29vZ2xlLnByb3RvYnVmLkVtcHR5SABSB3NpdERvd24SLwoEd2'
    'FsaxgEIAEoCzIZLmJyYWluc3RlbS5hcGkudjEuVmVjdG9yM0gAUgR3YWxrQgYKBGRhdGE=');

@$core.Deprecated('Use gestureRequestDescriptor instead')
const GestureRequest$json = {
  '1': 'GestureRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `GestureRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List gestureRequestDescriptor =
    $convert.base64Decode('Cg5HZXN0dXJlUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1l');

@$core.Deprecated('Use gestureListDescriptor instead')
const GestureList$json = {
  '1': 'GestureList',
  '2': [
    {
      '1': 'gestures',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.brainstem.api.v1.GestureInfo',
      '10': 'gestures'
    },
  ],
};

/// Descriptor for `GestureList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List gestureListDescriptor = $convert.base64Decode(
    'CgtHZXN0dXJlTGlzdBI5CghnZXN0dXJlcxgBIAMoCzIdLmJyYWluc3RlbS5hcGkudjEuR2VzdH'
    'VyZUluZm9SCGdlc3R1cmVz');

@$core.Deprecated('Use gestureInfoDescriptor instead')
const GestureInfo$json = {
  '1': 'GestureInfo',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    {'1': 'duration_ms', '3': 3, '4': 1, '5': 5, '10': 'durationMs'},
  ],
};

/// Descriptor for `GestureInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List gestureInfoDescriptor = $convert.base64Decode(
    'CgtHZXN0dXJlSW5mbxISCgRuYW1lGAEgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGAIgASgJUg'
    'tkZXNjcmlwdGlvbhIfCgtkdXJhdGlvbl9tcxgDIAEoBVIKZHVyYXRpb25Ncw==');

@$core.Deprecated('Use speedModeRequestDescriptor instead')
const SpeedModeRequest$json = {
  '1': 'SpeedModeRequest',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.brainstem.api.v1.SpeedMode',
      '10': 'mode'
    },
  ],
};

/// Descriptor for `SpeedModeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speedModeRequestDescriptor = $convert.base64Decode(
    'ChBTcGVlZE1vZGVSZXF1ZXN0Ei8KBG1vZGUYASABKA4yGy5icmFpbnN0ZW0uYXBpLnYxLlNwZW'
    'VkTW9kZVIEbW9kZQ==');
