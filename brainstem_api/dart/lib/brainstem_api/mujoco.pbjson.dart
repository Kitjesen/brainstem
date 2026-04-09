// This is a generated file - do not edit.
//
// Generated from brainstem_api/mujoco.proto.

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

@$core.Deprecated('Use viewerFrameDescriptor instead')
const ViewerFrame$json = {
  '1': 'ViewerFrame',
  '2': [
    {
      '1': 'qpos',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.ArrayFloat',
      '10': 'qpos'
    },
    {
      '1': 'qvel',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.brainstem.api.v1.ArrayFloat',
      '10': 'qvel'
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

/// Descriptor for `ViewerFrame`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List viewerFrameDescriptor = $convert.base64Decode(
    'CgtWaWV3ZXJGcmFtZRIwCgRxcG9zGAEgASgLMhwuYnJhaW5zdGVtLmFwaS52MS5BcnJheUZsb2'
    'F0UgRxcG9zEjAKBHF2ZWwYAiABKAsyHC5icmFpbnN0ZW0uYXBpLnYxLkFycmF5RmxvYXRSBHF2'
    'ZWwSNwoJdGltZXN0YW1wGAMgASgLMhkuZ29vZ2xlLnByb3RvYnVmLkR1cmF0aW9uUgl0aW1lc3'
    'RhbXA=');
