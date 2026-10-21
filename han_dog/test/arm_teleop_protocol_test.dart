import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:han_dog/han_dog.dart';
import 'package:test/test.dart';

Map<String, Object?> _ackPayload({
  int widthUm = 50,
  String sessionId = '',
  int sequence = -1,
  String activeProfile = armTeleopProfileFullGripper,
}) => <String, Object?>{
  'v': armTeleopProtocolVersion,
  'session_id': sessionId,
  'boot_id': 'ffeeddccbbaa99887766554433221100',
  'seq': sequence,
  'service_state': 'SAFE',
  'firmware': 'S-V1.9-0',
  'can_ok': true,
  'arm_ok': true,
  'active_profile': activeProfile,
  'capabilities': activeProfile == armTeleopProfileSixAxisOnly
      ? <String>['six_axis_motion']
      : <String>['six_axis_motion', 'gripper_motion'],
  'gripper_control_enabled': activeProfile == armTeleopProfileFullGripper,
  'gripper_available': activeProfile == armTeleopProfileFullGripper,
  'gripper_driver_enabled': activeProfile == armTeleopProfileFullGripper,
  'gripper_feedback_fresh': true,
  'joints_enabled': false,
  'joint_enable_states': <bool>[false, false, false, false, false, false],
  'gripper_ok': activeProfile == armTeleopProfileFullGripper,
  'gripper_width_um': activeProfile == armTeleopProfileFullGripper
      ? widthUm
      : null,
  'fault': '',
};

void main() {
  final secret = utf8.encode('0123456789abcdef0123456789abcdef');

  test('control packet HMAC matches Python golden vector', () {
    const packet = ArmTeleopControlPacket(
      sessionId: '00112233445566778899aabbccddeeff',
      armBootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sequence: 0,
      mode: 'neutral',
      armAllowed: false,
      stowRequest: false,
      estop: false,
      dogState: 'Grounded',
      lx: 0.0,
      ly: 0.0,
      rx: 0.0,
      ry: 0.0,
      lt: false,
      rt: false,
      armRequestId: 0,
      stowRequestId: 0,
      estopRequestId: 0,
    );
    final signed = signArmTeleopJson(packet.toJson(), secret);
    expect(packet.toJson()['v'], 2);
    expect(packet.toJson()['active_profile'], armTeleopProfileFullGripper);

    expect(
      signed['hmac'],
      '037a310b406e63fc507fb43fb2d9b9c01d472d5c3a4e580383723c6fcbd51166',
    );
    expect(
      decodeAndVerifyArmTeleopJson(packet.encode(secret), secret),
      isNotNull,
    );
  });

  test('axis fixed-point quantization matches Python vectors', () {
    expect(quantizeArmAxisPpm(-0.0), 0);
    expect(quantizeArmAxisPpm(1.0), 1000000);
    expect(quantizeArmAxisPpm(-1.0), -1000000);
    expect(quantizeArmAxisPpm(0.0000005), 1);
    expect(quantizeArmAxisPpm(-0.0000005), -1);
    expect(quantizeArmAxisPpm(1 / 720), 1389);

    const packet = ArmTeleopControlPacket(
      sessionId: '00112233445566778899aabbccddeeff',
      armBootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sequence: 0,
      mode: 'neutral',
      armAllowed: false,
      stowRequest: false,
      estop: false,
      dogState: 'Grounded',
      lx: 1 / 720,
      ly: -0.0,
      rx: 0,
      ry: 0,
      lt: false,
      rt: false,
      armRequestId: 0,
      stowRequestId: 0,
      estopRequestId: 0,
    );
    final signed = signArmTeleopJson(packet.toJson(), secret);
    expect(packet.toJson()['lx_ppm'], 1389);
    expect(packet.toJson()['ly_ppm'], 0);
    expect(
      signed['hmac'],
      '1c9a2ce0d07bb6b0bd7a2155b6fe69fc347e12fe3e7057e5d3e6f962153aaab6',
    );
  });

  test('signed wire recursively rejects every floating-point value', () {
    expect(
      () => signArmTeleopJson(<String, Object?>{
        'v': armTeleopProtocolVersion,
        'nested': <Object?>[
          <String, Object?>{'value': 0.00005},
        ],
      }, secret),
      throwsArgumentError,
    );

    final unsigned = <String, Object?>{
      'v': armTeleopProtocolVersion,
      'value': 0.00005,
    };
    final signature = Hmac(
      sha256,
      secret,
    ).convert(canonicalJsonBytes(unsigned)).toString();
    final maliciousWire = canonicalJsonBytes(<String, Object?>{
      ...unsigned,
      'hmac': signature,
    });
    expect(decodeAndVerifyArmTeleopJson(maliciousWire, secret), isNull);
  });

  test('tampering is rejected', () {
    const packet = ArmTeleopControlPacket(
      sessionId: 'session',
      armBootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sequence: 1,
      mode: 'neutral',
      armAllowed: false,
      stowRequest: false,
      estop: false,
      dogState: 'Grounded',
      lx: 0,
      ly: 0,
      rx: 0,
      ry: 0,
      lt: false,
      rt: false,
      armRequestId: 0,
      stowRequestId: 0,
      estopRequestId: 0,
    );
    final signed = signArmTeleopJson(packet.toJson(), secret);
    signed['arm_allowed'] = true;

    expect(
      decodeAndVerifyArmTeleopJson(canonicalJsonBytes(signed), secret),
      isNull,
    );
  });

  test('signed SAFE ACK with empty session exposes boot_id', () {
    final wire = encodeSignedArmTeleopJson(_ackPayload(), secret);

    final ack = ArmTeleopAck.decode(wire, secret);
    expect(ack, isNotNull);
    expect(ack!.sessionId, isEmpty);
    expect(ack.bootId, 'ffeeddccbbaa99887766554433221100');
    expect(ack.sequence, -1);
    expect(ack.gripperWidthUm, 50);
    expect(ack.gripperWidthM, closeTo(0.00005, 1e-12));

    final oneMicrometre = ArmTeleopAck.decode(
      encodeSignedArmTeleopJson(_ackPayload(widthUm: 1), secret),
      secret,
    );
    expect(oneMicrometre!.gripperWidthUm, 1);
    expect(oneMicrometre.gripperWidthM, closeTo(0.000001, 1e-12));
  });

  test('ACK parser requires the exact v2 field set', () {
    final v1 = _ackPayload()..['v'] = 1;
    expect(
      ArmTeleopAck.decode(encodeSignedArmTeleopJson(v1, secret), secret),
      isNull,
    );

    final missing = _ackPayload()..remove('gripper_feedback_fresh');
    expect(
      ArmTeleopAck.decode(encodeSignedArmTeleopJson(missing, secret), secret),
      isNull,
    );

    final extra = _ackPayload()..['future_field'] = false;
    expect(
      ArmTeleopAck.decode(encodeSignedArmTeleopJson(extra, secret), secret),
      isNull,
    );
  });

  test('six-axis-only ACK requires fresh feedback and proven driver off', () {
    final valid = ArmTeleopAck.decode(
      encodeSignedArmTeleopJson(
        _ackPayload(activeProfile: armTeleopProfileSixAxisOnly),
        secret,
      ),
      secret,
    );
    expect(valid, isNotNull);
    expect(valid!.healthy, isTrue);

    for (final unsafeDriver in <Object?>[true, null]) {
      final payload = _ackPayload(activeProfile: armTeleopProfileSixAxisOnly)
        ..['gripper_driver_enabled'] = unsafeDriver;
      final ack = ArmTeleopAck.decode(
        encodeSignedArmTeleopJson(payload, secret),
        secret,
      );
      expect(ack, isNotNull);
      expect(ack!.healthy, isFalse);
    }
  });

  test('capability order is an exact profile contract', () {
    final payload = _ackPayload()
      ..['capabilities'] = <String>['gripper_motion', 'six_axis_motion'];
    final ack = ArmTeleopAck.decode(
      encodeSignedArmTeleopJson(payload, secret),
      secret,
    );
    expect(ack, isNotNull);
    expect(ack!.capabilityContractValid, isFalse);
    expect(ack.healthy, isFalse);
  });
}
