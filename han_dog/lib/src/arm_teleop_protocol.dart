import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int armTeleopProtocolVersion = 2;

const String armTeleopProfileFullGripper = 'full_gripper';
const String armTeleopProfileSixAxisOnly = 'six_axis_only';

const List<String> armTeleopFullGripperCapabilities = <String>[
  'six_axis_motion',
  'gripper_motion',
];
const List<String> armTeleopSixAxisOnlyCapabilities = <String>[
  'six_axis_motion',
];

const Set<String> _armTeleopAckFields = <String>{
  'v',
  'boot_id',
  'session_id',
  'seq',
  'service_state',
  'firmware',
  'can_ok',
  'arm_ok',
  'active_profile',
  'capabilities',
  'gripper_control_enabled',
  'gripper_available',
  'gripper_driver_enabled',
  'gripper_feedback_fresh',
  'gripper_ok',
  'joints_enabled',
  'joint_enable_states',
  'gripper_width_um',
  'fault',
};

/// 生成每次进程启动唯一的认证会话 ID。
String newArmTeleopSessionId([Random? random]) {
  final source = random ?? Random.secure();
  return List<int>.generate(
    16,
    (_) => source.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

/// 跨 Dart/Python 确定的 canonical JSON：对象键递归字典序、无缩进、UTF-8。
Uint8List canonicalJsonBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(_canonicalize(value))));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError('Canonical JSON only supports string object keys');
      }
      sorted[entry.key as String] = _canonicalize(entry.value);
    }
    return sorted;
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
  if (value == null || value is String || value is bool || value is num) {
    if (value is num && !value.isFinite) {
      throw ArgumentError('Canonical JSON does not support non-finite numbers');
    }
    return value;
  }
  throw ArgumentError('Unsupported canonical JSON value: ${value.runtimeType}');
}

Map<String, Object?> signArmTeleopJson(
  Map<String, Object?> payload,
  List<int> secret,
) {
  if (secret.isEmpty) throw ArgumentError.value(secret, 'secret', 'is empty');
  final unsigned = Map<String, Object?>.of(payload)..remove('hmac');
  _validateArmWireJson(unsigned);
  final signature = Hmac(sha256, secret).convert(canonicalJsonBytes(unsigned));
  return <String, Object?>{...unsigned, 'hmac': signature.toString()};
}

Uint8List encodeSignedArmTeleopJson(
  Map<String, Object?> payload,
  List<int> secret,
) => canonicalJsonBytes(signArmTeleopJson(payload, secret));

Map<String, Object?>? decodeAndVerifyArmTeleopJson(
  List<int> wireBytes,
  List<int> secret,
) {
  try {
    final decoded = jsonDecode(utf8.decode(wireBytes));
    if (decoded is! Map<String, dynamic>) return null;
    final signature = decoded['hmac'];
    if (signature is! String || signature.length != 64) return null;
    final unsigned = Map<String, Object?>.from(decoded)..remove('hmac');
    _validateArmWireJson(unsigned);
    final expected = Hmac(
      sha256,
      secret,
    ).convert(canonicalJsonBytes(unsigned)).toString();
    if (!_constantTimeEquals(signature.toLowerCase(), expected)) return null;
    return unsigned;
  } on Object {
    return null;
  }
}

/// v1 签名线上对象只允许整数，彻底避开 Dart/Python 浮点 JSON 差异。
void _validateArmWireJson(Object? value) {
  if (value == null || value is String || value is bool || value is int) return;
  if (value is List) {
    for (final item in value) {
      _validateArmWireJson(item);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError('Arm wire JSON only supports string object keys');
      }
      _validateArmWireJson(entry.value);
    }
    return;
  }
  throw ArgumentError(
    'Arm wire JSON forbids ${value.runtimeType}; use fixed-point integers',
  );
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

class ArmTeleopControlPacket {
  final String sessionId;
  final String armBootId;
  final int sequence;
  final String mode;
  final String activeProfile;
  final bool armAllowed;
  final bool stowRequest;
  final bool estop;
  final String dogState;
  final double lx;
  final double ly;
  final double rx;
  final double ry;
  final bool lt;
  final bool rt;
  final int armRequestId;
  final int stowRequestId;
  final int estopRequestId;

  const ArmTeleopControlPacket({
    required this.sessionId,
    required this.armBootId,
    required this.sequence,
    required this.mode,
    this.activeProfile = armTeleopProfileFullGripper,
    required this.armAllowed,
    required this.stowRequest,
    required this.estop,
    required this.dogState,
    required this.lx,
    required this.ly,
    required this.rx,
    required this.ry,
    required this.lt,
    required this.rt,
    required this.armRequestId,
    required this.stowRequestId,
    required this.estopRequestId,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'v': armTeleopProtocolVersion,
    'session_id': sessionId,
    'arm_boot_id': armBootId,
    'seq': sequence,
    'mode': mode,
    'active_profile': activeProfile,
    'arm_allowed': armAllowed,
    'stow_request': stowRequest,
    'estop': estop,
    'dog_state': dogState,
    'lx_ppm': quantizeArmAxisPpm(lx),
    'ly_ppm': quantizeArmAxisPpm(ly),
    'rx_ppm': quantizeArmAxisPpm(rx),
    'ry_ppm': quantizeArmAxisPpm(ry),
    'lt': lt,
    'rt': rt,
    'arm_request_id': armRequestId,
    'stow_request_id': stowRequestId,
    'estop_request_id': estopRequestId,
  };

  Uint8List encode(List<int> secret) =>
      encodeSignedArmTeleopJson(toJson(), secret);
}

/// 将归一化轴量化为百万分之一；恰好半值时远离零，负零归零。
int quantizeArmAxisPpm(double value) {
  if (!value.isFinite) return 0;
  final scaled = value.clamp(-1.0, 1.0).toDouble() * 1000000;
  if (scaled == 0) return 0;
  return scaled.isNegative ? (scaled - 0.5).ceil() : (scaled + 0.5).floor();
}

class ArmTeleopAck {
  final String sessionId;
  final String bootId;
  final int sequence;
  final String serviceState;
  final String firmware;
  final bool canOk;
  final bool armOk;
  final String activeProfile;
  final List<String> capabilities;
  final bool gripperControlEnabled;
  final bool gripperAvailable;
  final bool? gripperDriverEnabled;
  final bool gripperFeedbackFresh;
  final bool jointsEnabled;
  final List<bool> jointEnableStates;
  final bool gripperOk;
  final int? gripperWidthUm;
  final String? fault;

  const ArmTeleopAck({
    required this.sessionId,
    required this.bootId,
    required this.sequence,
    required this.serviceState,
    required this.firmware,
    required this.canOk,
    required this.armOk,
    required this.activeProfile,
    required this.capabilities,
    required this.gripperControlEnabled,
    required this.gripperAvailable,
    required this.gripperDriverEnabled,
    required this.gripperFeedbackFresh,
    required this.jointsEnabled,
    required this.jointEnableStates,
    required this.gripperOk,
    required this.gripperWidthUm,
    required this.fault,
  });

  bool get capabilityContractValid =>
      _listEquals(capabilities, switch (activeProfile) {
        armTeleopProfileFullGripper => armTeleopFullGripperCapabilities,
        armTeleopProfileSixAxisOnly => armTeleopSixAxisOnlyCapabilities,
        _ => const <String>[],
      });

  /// Profile-specific gripper contract. In six-axis-only mode no gripper
  /// command can be transmitted, so admission requires an explicit driver-off
  /// bit but does not depend on the broken gripper's source timestamp.
  bool get gripperContractValid => switch (activeProfile) {
    armTeleopProfileFullGripper =>
      gripperControlEnabled &&
          gripperAvailable &&
          gripperDriverEnabled == true &&
          gripperFeedbackFresh &&
          gripperOk,
    armTeleopProfileSixAxisOnly =>
      !gripperControlEnabled &&
          !gripperAvailable &&
          gripperDriverEnabled == false &&
          !gripperOk,
    _ => false,
  };

  bool get healthy =>
      canOk &&
      armOk &&
      capabilityContractValid &&
      gripperContractValid &&
      (fault == null || fault!.isEmpty);

  bool matchesRequestedProfile(String requestedProfile) =>
      activeProfile == requestedProfile && capabilityContractValid;

  double? get gripperWidthM =>
      gripperWidthUm == null ? null : gripperWidthUm! / 1000000.0;

  static ArmTeleopAck? decode(List<int> wireBytes, List<int> secret) {
    final json = decodeAndVerifyArmTeleopJson(wireBytes, secret);
    return json == null ? null : fromVerifiedJson(json);
  }

  /// Parses an already HMAC-verified ACK. The key set is exact: v1 ACKs,
  /// omitted safety fields, and forward-incompatible extras all fail closed.
  static ArmTeleopAck? fromVerifiedJson(Map<String, Object?> json) {
    if (!_setEquals(json.keys.toSet(), _armTeleopAckFields) ||
        json['v'] != armTeleopProtocolVersion ||
        json['session_id'] is! String ||
        json['boot_id'] is! String ||
        json['seq'] is! int ||
        json['service_state'] is! String ||
        json['firmware'] is! String ||
        json['can_ok'] is! bool ||
        json['arm_ok'] is! bool ||
        json['active_profile'] is! String ||
        json['capabilities'] is! List ||
        (json['capabilities']! as List).any((value) => value is! String) ||
        json['gripper_control_enabled'] is! bool ||
        json['gripper_available'] is! bool ||
        (json['gripper_driver_enabled'] != null &&
            json['gripper_driver_enabled'] is! bool) ||
        json['gripper_feedback_fresh'] is! bool ||
        json['joints_enabled'] is! bool ||
        json['gripper_ok'] is! bool) {
      return null;
    }
    final sessionId = json['session_id']! as String;
    final bootId = json['boot_id']! as String;
    final sequence = json['seq']! as int;
    final idPattern = RegExp(r'^[0-9a-f]{32}$');
    if (!idPattern.hasMatch(bootId) ||
        (sessionId.isNotEmpty && !idPattern.hasMatch(sessionId)) ||
        (sessionId.isEmpty ? sequence != -1 : sequence < 0)) {
      return null;
    }
    final faultValue = json['fault'];
    if (faultValue is! String) return null;
    final jointStatesValue = json['joint_enable_states'];
    if (jointStatesValue is! List ||
        jointStatesValue.length != 6 ||
        jointStatesValue.any((value) => value is! bool)) {
      return null;
    }
    final jointEnableStates = List<bool>.unmodifiable(
      jointStatesValue.cast<bool>(),
    );
    final gripperWidthValue = json['gripper_width_um'];
    if (gripperWidthValue != null &&
        (gripperWidthValue is! int || gripperWidthValue < 0)) {
      return null;
    }
    final activeProfile = json['active_profile']! as String;
    if (activeProfile != armTeleopProfileFullGripper &&
        activeProfile != armTeleopProfileSixAxisOnly) {
      return null;
    }
    return ArmTeleopAck(
      sessionId: sessionId,
      bootId: bootId,
      sequence: sequence,
      serviceState: json['service_state']! as String,
      firmware: json['firmware']! as String,
      canOk: json['can_ok']! as bool,
      armOk: json['arm_ok']! as bool,
      activeProfile: activeProfile,
      capabilities: List<String>.unmodifiable(
        (json['capabilities']! as List).cast<String>(),
      ),
      gripperControlEnabled: json['gripper_control_enabled']! as bool,
      gripperAvailable: json['gripper_available']! as bool,
      gripperDriverEnabled: json['gripper_driver_enabled'] as bool?,
      gripperFeedbackFresh: json['gripper_feedback_fresh']! as bool,
      jointsEnabled: json['joints_enabled']! as bool,
      jointEnableStates: jointEnableStates,
      gripperOk: json['gripper_ok']! as bool,
      gripperWidthUm: gripperWidthValue as int?,
      fault: faultValue,
    );
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);
