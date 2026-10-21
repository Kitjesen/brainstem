import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:han_dog/han_dog.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const _secretText = '0123456789abcdef0123456789abcdef';
final _secret = utf8.encode(_secretText);

YunZhuoControlFrame _frame({
  required DateTime at,
  bool l1 = false,
  bool l2 = false,
  bool red = false,
  bool lt = false,
  bool rt = false,
  bool modeChanged = false,
  YunZhuoControlMode mode = YunZhuoControlMode.arm,
  Vector2? left,
  Vector2? right,
}) {
  final channels = List<int>.filled(16, SbusValues.low);
  // Live H20/R20 shoulder buttons are active-low: released=high, pressed=low.
  channels[10] = l1 ? SbusValues.low : SbusValues.high;
  channels[6] = l2 ? SbusValues.low : SbusValues.high;
  channels[4] = switch (mode) {
    YunZhuoControlMode.dog => SbusValues.high,
    YunZhuoControlMode.neutral => SbusValues.center,
    YunZhuoControlMode.arm => SbusValues.low,
  };
  return YunZhuoControlFrame(
    receivedAt: at,
    mode: YunZhuoModeSnapshot(
      mode: mode,
      dogDriveScale: mode == YunZhuoControlMode.dog ? 1 : 0,
      neutralGateReady: false,
      modeChanged: modeChanged,
    ),
    state: YunZhuoState(
      L1: l1,
      L2: l2,
      R1: false,
      R2: false,
      leftStick: left ?? Vector2.zero(),
      rightStick: right ?? Vector2.zero(),
      H: true,
      G_S: switch (mode) {
        YunZhuoControlMode.dog => GSState.up,
        YunZhuoControlMode.neutral => GSState.middle,
        YunZhuoControlMode.arm => GSState.down,
      },
      red: red,
      LT: lt,
      RT: rt,
      knob: 0,
      rawChannels: channels,
    ),
  );
}

Map<String, Object?> _ack({
  required String sessionId,
  required String bootId,
  required int sequence,
  String serviceState = 'SAFE',
  String activeProfile = armTeleopProfileFullGripper,
}) => <String, Object?>{
  'v': armTeleopProtocolVersion,
  'session_id': sessionId,
  'boot_id': bootId,
  'seq': sequence,
  'service_state': serviceState,
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
      ? 50000
      : null,
  'fault': '',
};

Future<int> _unusedUdpPort() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  socket.close();
  return port;
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not satisfied within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('machine-dog arm safety gate', () {
    test('Grounded commissioning path tolerates missing leg feedback', () {
      expect(
        isDogSafeForArmTeleop(
          dogState: 'Grounded',
          allActuatorFeedbackFresh: false,
          motorOutputEnabled: false,
        ),
        isTrue,
      );
    });

    test('Standing still requires all feedback and motor hold output', () {
      for (final unsafe in <(bool, bool)>[
        (false, false),
        (false, true),
        (true, false),
      ]) {
        expect(
          isDogSafeForArmTeleop(
            dogState: 'Standing',
            allActuatorFeedbackFresh: unsafe.$1,
            motorOutputEnabled: unsafe.$2,
          ),
          isFalse,
        );
      }
      expect(
        isDogSafeForArmTeleop(
          dogState: 'Standing',
          allActuatorFeedbackFresh: true,
          motorOutputEnabled: true,
        ),
        isTrue,
      );
    });

    test('Walking, Transitioning, and fault-like states always reject', () {
      for (final state in <String>[
        'Walking',
        'Transitioning',
        'Fault',
        'Zero',
        'Unknown',
      ]) {
        expect(
          isDogSafeForArmTeleop(
            dogState: state,
            allActuatorFeedbackFresh: true,
            motorOutputEnabled: true,
          ),
          isFalse,
        );
      }
    });
  });

  test('placeholder HMAC secret fails closed', () {
    expect(
      () => const ArmTeleopBridgeConfig(
        secret: 'replace-with-a-real-random-secret-1234567890',
      ).validate(),
      throwsArgumentError,
    );
  });

  test(
    'encoder exceptions stay inside bridge and dispose is best effort',
    () async {
      final ackPort = await _unusedUdpPort();
      final frames = StreamController<YunZhuoControlFrame>.broadcast();
      final bridge = ArmTeleopBridge(
        frames: frames.stream,
        dogStateProvider: () => 'Grounded',
        dogSafetyProvider: () => true,
        packetEncoder: (_, _) => throw StateError('simulated encoder failure'),
        config: ArmTeleopBridgeConfig(
          remoteHost: '127.0.0.1',
          controlPort: 9,
          ackPort: ackPort,
          secret: _secretText,
        ),
      );

      await expectLater(bridge.start(), completes);
      expect(bridge.transportFaulted, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await expectLater(bridge.dispose(), completes);
      await frames.close();
    },
  );

  test('ACK receive exceptions stay inside bridge and revoke motion', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final ackPort = await _unusedUdpPort();
    final frames = StreamController<YunZhuoControlFrame>.broadcast();
    final bridge = ArmTeleopBridge(
      frames: frames.stream,
      dogStateProvider: () => 'Grounded',
      dogSafetyProvider: () => true,
      datagramReceiver: (socket) {
        socket.receive();
        throw StateError('simulated UDP receive failure');
      },
      config: ArmTeleopBridgeConfig(
        remoteHost: '127.0.0.1',
        controlPort: server.port,
        ackPort: ackPort,
        secret: _secretText,
      ),
    );

    await bridge.start();
    server.send(<int>[0], InternetAddress.loopbackIPv4, ackPort);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(bridge.transportFaulted, isTrue);
    expect(bridge.armAllowed, isFalse);
    expect(bridge.holdAckRequired, isTrue);

    await expectLater(bridge.dispose(), completes);
    await frames.close();
    server.close();
  });

  test(
    'active-low L2 held while entering arm must be released before a press',
    () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final received = <Map<String, Object?>>[];
      final serverSub = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = server.receive()) != null) {
          final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
          if (decoded != null) received.add(decoded);
        }
      });
      final frames = StreamController<YunZhuoControlFrame>.broadcast(
        sync: true,
      );
      final bridge = ArmTeleopBridge(
        frames: frames.stream,
        dogStateProvider: () => 'Grounded',
        dogSafetyProvider: () => true,
        config: ArmTeleopBridgeConfig(
          remoteHost: '127.0.0.1',
          controlPort: server.port,
          ackPort: await _unusedUdpPort(),
          secret: _secretText,
          sendPeriod: const Duration(seconds: 1),
          inputTimeout: const Duration(seconds: 10),
        ),
      );

      await bridge.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      frames.add(_frame(at: DateTime.now(), l2: true, modeChanged: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final afterEntry = received.length;

      // Releasing a button that was already held during the mode transition is
      // only the interlock reset. It is not an L2 short press/HOLD event.
      frames.add(_frame(at: DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, hasLength(afterEntry));
      expect(bridge.holdAckRequired, isFalse);

      await bridge.dispose();
      await frames.close();
      await serverSub.cancel();
      server.close();
    },
  );

  test(
    'unarmed unhealthy SAFE ACK settles without HOLD handshake churn',
    () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final ackPort = await _unusedUdpPort();
      final controls = StreamController<Map<String, Object?>>.broadcast();
      final receivedControls = <Map<String, Object?>>[];
      final serverSub = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = server.receive()) != null) {
          final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
          if (decoded == null) continue;
          receivedControls.add(decoded);
          controls.add(decoded);
        }
      });
      final frames = StreamController<YunZhuoControlFrame>.broadcast(
        sync: true,
      );
      final bridge = ArmTeleopBridge(
        frames: frames.stream,
        dogStateProvider: () => 'Grounded',
        dogSafetyProvider: () => true,
        clock: DateTime.now,
        sessionId: '00112233445566778899aabbccddeeff',
        config: ArmTeleopBridgeConfig(
          remoteHost: '127.0.0.1',
          controlPort: server.port,
          ackPort: ackPort,
          secret: _secretText,
          sendPeriod: const Duration(seconds: 1),
          inputTimeout: const Duration(seconds: 10),
        ),
      );

      final discoveryFuture = controls.stream.first;
      await bridge.start();
      await discoveryFuture.timeout(const Duration(seconds: 2));

      final boundFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_boot_id'] == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' &&
            packet['mode'] == 'neutral',
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: '',
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: -1,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      final bound = await boundFuture.timeout(const Duration(seconds: 2));

      Map<String, Object?> gripperNotHomedAck(int sequence) {
        final ack = _ack(
          sessionId: bridge.sessionId,
          bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sequence: sequence,
          serviceState: 'SAFE',
        );
        ack['gripper_ok'] = false;
        ack['fault'] = 'gripper_not_homed';
        return ack;
      }

      server.send(
        encodeSignedArmTeleopJson(
          gripperNotHomedAck(bound['seq']! as int),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bridge.armAllowed, isFalse);
      expect(bridge.holdAckRequired, isFalse);
      final controlsAfterFirstUnhealthyAck = receivedControls.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedControls, hasLength(controlsAfterFirstUnhealthyAck));

      // 新的普通 neutral 包收到同一预存异常后也应稳定，不额外补发撤权包。
      final repeatedNeutralFuture = controls.stream.firstWhere(
        (packet) =>
            (packet['seq']! as int) > (bound['seq']! as int) &&
            packet['mode'] == 'neutral',
      );
      frames.add(
        _frame(
          at: DateTime.now(),
          mode: YunZhuoControlMode.neutral,
          modeChanged: true,
        ),
      );
      final repeatedNeutral = await repeatedNeutralFuture.timeout(
        const Duration(seconds: 2),
      );
      server.send(
        encodeSignedArmTeleopJson(
          gripperNotHomedAck(repeatedNeutral['seq']! as int),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bridge.holdAckRequired, isFalse);
      final controlsAfterRepeatedUnhealthyAck = receivedControls.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedControls, hasLength(controlsAfterRepeatedUnhealthyAck));

      // 恢复健康 SAFE 后可明确授权；授权期间真正的 FAULT 仍必须撤权并
      // 建立 HOLD ACK 屏障。
      final healthyNeutralFuture = controls.stream.firstWhere(
        (packet) =>
            (packet['seq']! as int) > (repeatedNeutral['seq']! as int) &&
            packet['mode'] == 'neutral',
      );
      frames.add(
        _frame(
          at: DateTime.now(),
          mode: YunZhuoControlMode.neutral,
          modeChanged: true,
        ),
      );
      final healthyNeutral = await healthyNeutralFuture.timeout(
        const Duration(seconds: 2),
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: healthyNeutral['seq']! as int,
            serviceState: 'SAFE',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.lastAck?.healthy, isTrue);

      frames.add(_frame(at: DateTime.now(), modeChanged: true));
      final authorizedFuture = controls.stream.firstWhere(
        (packet) => packet['arm_allowed'] == true,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      final authorized = await authorizedFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(bridge.armAllowed, isTrue);

      final revokedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == false &&
            (packet['seq']! as int) > (authorized['seq']! as int),
      );
      final faultAck = _ack(
        sessionId: bridge.sessionId,
        bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: authorized['seq']! as int,
        serviceState: 'FAULT',
      );
      faultAck['arm_ok'] = false;
      faultAck['fault'] = 'simulated_active_fault';
      server.send(
        encodeSignedArmTeleopJson(faultAck, _secret),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await revokedFuture.timeout(const Duration(seconds: 2));
      expect(bridge.armAllowed, isFalse);
      expect(bridge.holdAckRequired, isTrue);

      await bridge.dispose();
      await frames.close();
      await serverSub.cancel();
      await controls.close();
      server.close();
    },
  );

  test(
    'lost first HOLD packet blocks fast L1 until ACK crosses barrier',
    () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final ackPort = await _unusedUdpPort();
      final controls = StreamController<Map<String, Object?>>.broadcast();
      final serverSub = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = server.receive()) != null) {
          final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
          if (decoded != null) controls.add(decoded);
        }
      });
      final frames = StreamController<YunZhuoControlFrame>.broadcast(
        sync: true,
      );
      var dropNext = false;
      final bridge = ArmTeleopBridge(
        frames: frames.stream,
        dogStateProvider: () => 'Grounded',
        dogSafetyProvider: () => true,
        clock: DateTime.now,
        datagramSender: (socket, bytes, address, port) {
          if (dropNext) {
            dropNext = false;
            return bytes.length; // 模拟内核接受、网络丢失该撤权包。
          }
          return socket.send(bytes, address, port);
        },
        sessionId: '00112233445566778899aabbccddeeff',
        config: ArmTeleopBridgeConfig(
          remoteHost: '127.0.0.1',
          controlPort: server.port,
          ackPort: ackPort,
          secret: _secretText,
          sendPeriod: const Duration(seconds: 1),
        ),
      );

      final discoveryFuture = controls.stream.first;
      await bridge.start();
      await discoveryFuture.timeout(const Duration(seconds: 2));
      final boundFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_boot_id'] == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' &&
            packet['mode'] == 'neutral',
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: '',
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: -1,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      final bound = await boundFuture.timeout(const Duration(seconds: 2));
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: bound['seq']! as int,
            serviceState: 'HOLD',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.holdAckRequired, isFalse);

      frames.add(_frame(at: DateTime.now(), modeChanged: true));
      final armedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true && packet['arm_request_id'] == 1,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      final armed = await armedFuture.timeout(const Duration(seconds: 2));
      frames.add(_frame(at: DateTime.now())); // 释放 L1，建立下一上升沿。

      final l2DownFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true &&
            packet['seq'] != armed['seq'] &&
            packet['stow_request'] == false,
      );
      frames.add(_frame(at: DateTime.now(), l2: true));
      final l2Down = await l2DownFuture.timeout(const Duration(seconds: 2));
      expect(l2Down['arm_request_id'], 1);
      expect(l2Down['stow_request'], isFalse);

      dropNext = true;
      frames.add(_frame(at: DateTime.now())); // L2 短按撤权，首包被丢弃。
      final barrier = bridge.holdAckBarrierSequence;
      expect(barrier, isNotNull);
      expect(bridge.holdAckRequired, isTrue);

      final laterFalseFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == false &&
            (packet['seq']! as int) > barrier!,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      final laterFalse = await laterFalseFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(laterFalse['arm_request_id'], 1);
      expect(bridge.armAllowed, isFalse);

      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: laterFalse['seq']! as int,
            serviceState: 'HOLD',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.holdAckRequired, isFalse);

      frames.add(_frame(at: DateTime.now()));
      final rearmedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true && packet['arm_request_id'] == 2,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      await rearmedFuture.timeout(const Duration(seconds: 2));

      await bridge.dispose();
      await frames.close();
      await serverSub.cancel();
      await controls.close();
      server.close();
    },
  );

  test(
    'L2 long hold emits one stow event and stays motion-authorized',
    () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final ackPort = await _unusedUdpPort();
      final controls = StreamController<Map<String, Object?>>.broadcast();
      final serverSub = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = server.receive()) != null) {
          final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
          if (decoded != null) controls.add(decoded);
        }
      });
      final frames = StreamController<YunZhuoControlFrame>.broadcast(
        sync: true,
      );
      var now = DateTime.utc(2026);
      final bridge = ArmTeleopBridge(
        frames: frames.stream,
        dogStateProvider: () => 'Standing',
        dogSafetyProvider: () => true,
        clock: () => now,
        sessionId: '00112233445566778899aabbccddeeff',
        config: ArmTeleopBridgeConfig(
          remoteHost: '127.0.0.1',
          controlPort: server.port,
          ackPort: ackPort,
          secret: _secretText,
          sendPeriod: const Duration(milliseconds: 5),
          ackTimeout: const Duration(seconds: 10),
          inputTimeout: const Duration(seconds: 10),
        ),
      );

      final discoveryFuture = controls.stream.first;
      await bridge.start();
      await discoveryFuture.timeout(const Duration(seconds: 2));

      final boundFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_boot_id'] == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' &&
            packet['mode'] == 'neutral',
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: '',
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: -1,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      final bound = await boundFuture.timeout(const Duration(seconds: 2));
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: bound['seq']! as int,
            serviceState: 'HOLD',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.holdAckRequired, isFalse);

      frames.add(_frame(at: now, modeChanged: true));
      now = now.add(const Duration(milliseconds: 10));
      final armedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true && packet['arm_request_id'] == 1,
      );
      frames.add(_frame(at: now, l1: true));
      final authorized = await armedFuture.timeout(const Duration(seconds: 2));
      expect(bridge.armAllowed, isTrue);

      // L1 之前已经在网络中的 HOLD ACK 可能晚到。只要它的 seq 尚未覆盖
      // 首个 arm_allowed=true 包，就不能撤销这次新授权。
      final authorizedSequence = authorized['seq']! as int;
      final boundSequence = bound['seq']! as int;
      final oldHoldSequence = authorizedSequence - 1;
      expect(oldHoldSequence, greaterThan(boundSequence));
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: oldHoldSequence,
            serviceState: 'HOLD',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bridge.armAllowed, isTrue);

      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: authorizedSequence,
            serviceState: 'ARMING',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bridge.armAllowed, isTrue);

      // ARMING 期间继续发 arm_allowed=true 保持授权，但摇杆必须归零。
      now = now.add(const Duration(milliseconds: 10));
      final gatedActionsFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true &&
            packet['arm_request_id'] == 1 &&
            packet['lx_ppm'] == 0 &&
            (packet['seq']! as int) > (authorized['seq']! as int),
      );
      frames.add(_frame(at: now, left: Vector2(0.5, 0)));
      final gatedActions = await gatedActionsFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(bridge.armAllowed, isTrue);

      // 已授权/ARMING 期间再按 L1 只忽略，不撤权也不递增事件。
      now = now.add(const Duration(milliseconds: 10));
      final duplicateL1Future = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true &&
            packet['arm_request_id'] == 1 &&
            (packet['seq']! as int) > (gatedActions['seq']! as int),
      );
      frames.add(_frame(at: now, l1: true));
      final duplicateL1 = await duplicateL1Future.timeout(
        const Duration(seconds: 2),
      );
      expect(bridge.armAllowed, isTrue);

      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: duplicateL1['seq']! as int,
            serviceState: 'ARMED',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bridge.armAllowed, isTrue);

      // 只有新鲜 ARMED 回执后才放行摇杆。
      now = now.add(const Duration(milliseconds: 10));
      final armedActionsFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true &&
            packet['lx_ppm'] == 250000 &&
            (packet['seq']! as int) > (duplicateL1['seq']! as int),
      );
      frames.add(_frame(at: now, left: Vector2(0.25, 0)));
      await armedActionsFuture.timeout(const Duration(seconds: 2));

      now = now.add(const Duration(milliseconds: 80));
      final l2DownFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true &&
            packet['stow_request'] == false &&
            packet['stow_request_id'] == 0,
      );
      frames.add(_frame(at: now, l2: true));
      await l2DownFuture.timeout(const Duration(seconds: 2));

      now = now.add(const Duration(milliseconds: 1499));
      frames.add(_frame(at: now, l2: true));
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final packetsBeforeThreshold = <Map<String, Object?>>[];
      final beforeSub = controls.stream.listen(packetsBeforeThreshold.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        packetsBeforeThreshold.any((packet) => packet['stow_request'] == true),
        isFalse,
      );
      await beforeSub.cancel();

      now = now.add(const Duration(milliseconds: 1));
      final stowFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true &&
            packet['stow_request'] == true &&
            packet['stow_request_id'] == 1,
      );
      frames.add(_frame(at: now, l2: true));
      final stow = await stowFuture.timeout(const Duration(seconds: 2));
      expect(stow['mode'], 'arm');
      expect(bridge.armAllowed, isTrue);

      // 周期包可重复携带当前请求，但事件 ID 只递增一次。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.armAllowed, isTrue);
      now = now.add(const Duration(milliseconds: 1));
      final releasedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['stow_request'] == false &&
            packet['stow_request_id'] == 1 &&
            (packet['seq']! as int) > (stow['seq']! as int),
      );
      frames.add(_frame(at: now));
      final released = await releasedFuture.timeout(const Duration(seconds: 2));
      expect(bridge.armAllowed, isTrue);

      final unknownStateRevokedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == false &&
            (packet['seq']! as int) > (released['seq']! as int),
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: released['seq']! as int,
            serviceState: 'UNKNOWN_FUTURE_STATE',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await unknownStateRevokedFuture.timeout(const Duration(seconds: 2));
      expect(bridge.armAllowed, isFalse);

      now = now.add(const Duration(milliseconds: 1));
      final quietModeFuture = controls.stream.firstWhere(
        (packet) =>
            packet['mode'] == 'dog' &&
            (packet['seq']! as int) > (released['seq']! as int),
      );
      frames.add(
        _frame(at: now, mode: YunZhuoControlMode.dog, modeChanged: true),
      );
      final quietMode = await quietModeFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(quietMode['arm_allowed'], isFalse);
      expect(quietMode['stow_request'], isFalse);
      expect(quietMode['lx_ppm'], 0);
      expect(quietMode['ly_ppm'], 0);
      expect(quietMode['rx_ppm'], 0);
      expect(quietMode['ry_ppm'], 0);

      await bridge.dispose();
      await frames.close();
      await serverSub.cancel();
      await controls.close();
      server.close();
    },
  );

  test('duplicate ACK cannot refresh freshness', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final ackPort = await _unusedUdpPort();
    final controls = StreamController<Map<String, Object?>>.broadcast();
    final serverSub = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = server.receive()) != null) {
        final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
        if (decoded != null) controls.add(decoded);
      }
    });
    var now = DateTime.utc(2026);
    final frames = StreamController<YunZhuoControlFrame>.broadcast();
    final bridge = ArmTeleopBridge(
      frames: frames.stream,
      dogStateProvider: () => 'Grounded',
      dogSafetyProvider: () => true,
      clock: () => now,
      sessionId: '00112233445566778899aabbccddeeff',
      config: ArmTeleopBridgeConfig(
        remoteHost: '127.0.0.1',
        controlPort: server.port,
        ackPort: ackPort,
        secret: _secretText,
        l2HoldDuration: const Duration(milliseconds: 30),
      ),
    );

    final bootstrapFuture = controls.stream.first;
    await bridge.start();
    final bootstrap = await bootstrapFuture.timeout(const Duration(seconds: 2));
    expect(bootstrap['arm_boot_id'], '');
    final boundBootstrapFuture = controls.stream.firstWhere(
      (packet) =>
          packet['arm_boot_id'] == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' &&
          packet['mode'] == 'neutral',
    );
    server.send(
      encodeSignedArmTeleopJson(
        _ack(
          sessionId: '',
          bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sequence: -1,
        ),
        _secret,
      ),
      InternetAddress.loopbackIPv4,
      ackPort,
    );
    final boundBootstrap = await boundBootstrapFuture.timeout(
      const Duration(seconds: 2),
    );
    final seq = boundBootstrap['seq']! as int;
    final ackBytes = encodeSignedArmTeleopJson(
      _ack(
        sessionId: bridge.sessionId,
        bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: seq,
      ),
      _secret,
    );
    server.send(ackBytes, InternetAddress.loopbackIPv4, ackPort);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(bridge.ackFresh, isTrue);

    now = now.add(const Duration(milliseconds: 400));
    server.send(ackBytes, InternetAddress.loopbackIPv4, ackPort);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    now = now.add(const Duration(milliseconds: 101));
    expect(bridge.ackFresh, isFalse);

    await bridge.dispose();
    await frames.close();
    await serverSub.cancel();
    await controls.close();
    server.close();
  });

  test(
    'hard stop interlocks motion and boot change sends safe ESTOP',
    () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final ackPort = await _unusedUdpPort();
      final controls = StreamController<Map<String, Object?>>.broadcast();
      final serverSub = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = server.receive()) != null) {
          final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
          if (decoded != null) controls.add(decoded);
        }
      });
      final frames = StreamController<YunZhuoControlFrame>.broadcast();
      final hardStops = StreamController<void>.broadcast();
      var failSends = false;
      final bridge = ArmTeleopBridge(
        frames: frames.stream,
        hardStops: hardStops.stream,
        dogStateProvider: () => 'Grounded',
        dogSafetyProvider: () => true,
        clock: DateTime.now,
        datagramSender: (socket, bytes, address, port) {
          if (failSends) throw StateError('simulated UDP send failure');
          return socket.send(bytes, address, port);
        },
        sessionId: '00112233445566778899aabbccddeeff',
        config: ArmTeleopBridgeConfig(
          remoteHost: '127.0.0.1',
          controlPort: server.port,
          ackPort: ackPort,
          secret: _secretText,
        ),
      );

      final bootstrapFuture = controls.stream.first;
      await bridge.start();
      final bootstrap = await bootstrapFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(bootstrap['arm_boot_id'], '');
      final boundBootstrapFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_boot_id'] == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' &&
            packet['mode'] == 'neutral',
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: '',
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: -1,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      final boundBootstrap = await boundBootstrapFuture.timeout(
        const Duration(seconds: 2),
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: boundBootstrap['seq']! as int,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      frames.add(_frame(at: DateTime.now(), modeChanged: true, lt: true));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      frames.add(_frame(at: DateTime.now(), l1: true, lt: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bridge.armAllowed, isFalse);
      frames.add(_frame(at: DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final armedPacketFuture = controls.stream.firstWhere(
        (packet) => packet['arm_allowed'] == true,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      final armed = await armedPacketFuture.timeout(const Duration(seconds: 2));
      expect(armed['arm_request_id'], 1);

      final holdCommandFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == false &&
            (packet['seq']! as int) > (armed['seq']! as int),
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: armed['seq']! as int,
            serviceState: 'HOLD',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.armAllowed, isFalse);
      expect(bridge.holdAckRequired, isTrue);
      final holdCommand = await holdCommandFuture.timeout(
        const Duration(seconds: 2),
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: holdCommand['seq']! as int,
            serviceState: 'HOLD',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bridge.holdAckRequired, isFalse);

      frames.add(_frame(at: DateTime.now()));
      final rearmedPacketFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true && packet['arm_request_id'] == 2,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      final rearmed = await rearmedPacketFuture.timeout(
        const Duration(seconds: 2),
      );

      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: rearmed['seq']! as int,
            serviceState: 'ARMED',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      failSends = true;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(bridge.transportFaulted, isTrue);
      expect(bridge.armAllowed, isFalse);

      final recoveredSafeFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == false &&
            (packet['seq']! as int) > (rearmed['seq']! as int),
      );
      failSends = false;
      final recoveredSafe = await recoveredSafeFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(bridge.transportFaulted, isFalse);

      // 旧 ARMED ACK 不能直接重新授权；必须先观察远端 SAFE/HOLD。
      frames.add(_frame(at: DateTime.now()));
      frames.add(_frame(at: DateTime.now(), l1: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bridge.armAllowed, isFalse);

      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: recoveredSafe['seq']! as int,
            serviceState: 'HOLD',
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      frames.add(_frame(at: DateTime.now()));
      final rearmedAfterTransportFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true && packet['arm_request_id'] == 3,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      final rearmedAfterTransport = await rearmedAfterTransportFuture.timeout(
        const Duration(seconds: 2),
      );

      final rejectedStowFuture = controls.stream.firstWhere(
        (packet) =>
            packet['mode'] == 'arm' &&
            packet['arm_allowed'] == false &&
            (packet['seq']! as int) > (rearmedAfterTransport['seq']! as int),
      );
      frames.add(_frame(at: DateTime.now(), l2: true, left: Vector2(0.5, 0)));
      final rejectedStow = await rejectedStowFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(rejectedStow['stow_request'], false);
      expect(bridge.armAllowed, isFalse);

      final stopPacketFuture = controls.stream.firstWhere(
        (packet) =>
            packet['mode'] == 'neutral' && packet['arm_allowed'] == false,
      );
      hardStops.add(null);
      final stopped = await stopPacketFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(stopped['lx_ppm'], 0);
      expect(stopped['lt'], false);
      expect(bridge.armAllowed, isFalse);

      final estopPacketFuture = controls.stream.firstWhere(
        (packet) => packet['estop'] == true,
      );
      frames.add(_frame(at: DateTime.now(), red: true));
      final estop = await estopPacketFuture.timeout(const Duration(seconds: 2));
      expect(estop['estop_request_id'], 1);

      final restartSafeFuture = controls.stream.firstWhere(
        (packet) =>
            packet['mode'] == 'neutral' &&
            packet['arm_boot_id'] == 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' &&
            packet['arm_allowed'] == false &&
            packet['estop'] == true &&
            (packet['seq']! as int) > (estop['seq']! as int),
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: '',
            bootId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            sequence: -1,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      final restartSafe = await restartSafeFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(restartSafe['estop_request_id'], 1);
      expect(restartSafe['stow_request'], false);

      await bridge.dispose();
      await frames.close();
      await hardStops.close();
      await serverSub.cancel();
      await controls.close();
      server.close();
    },
  );

  test('stale actuator feedback revokes ongoing arm permission', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final ackPort = await _unusedUdpPort();
    final controls = StreamController<Map<String, Object?>>.broadcast();
    final serverSub = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = server.receive()) != null) {
        final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
        if (decoded != null) controls.add(decoded);
      }
    });
    var now = DateTime.utc(2026);
    final freshness = ActuatorFeedbackFreshness(
      maxAge: const Duration(milliseconds: 100),
      clock: () => now,
    );
    for (var index = 0; index < hanDogActuatorCount; index++) {
      freshness.record(index);
    }
    final frames = StreamController<YunZhuoControlFrame>.broadcast(sync: true);
    final bridge = ArmTeleopBridge(
      frames: frames.stream,
      dogStateProvider: () => 'Grounded',
      dogSafetyProvider: () => freshness.allFresh,
      clock: () => now,
      sessionId: '00112233445566778899aabbccddeeff',
      config: ArmTeleopBridgeConfig(
        remoteHost: '127.0.0.1',
        controlPort: server.port,
        ackPort: ackPort,
        secret: _secretText,
        sendPeriod: const Duration(milliseconds: 10),
        ackTimeout: const Duration(seconds: 1),
        inputTimeout: const Duration(seconds: 1),
      ),
    );

    final discoveryFuture = controls.stream.first;
    await bridge.start();
    await discoveryFuture.timeout(const Duration(seconds: 2));

    final boundBootstrapFuture = controls.stream.firstWhere(
      (packet) =>
          packet['arm_boot_id'] == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' &&
          packet['mode'] == 'neutral',
    );
    server.send(
      encodeSignedArmTeleopJson(
        _ack(
          sessionId: '',
          bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sequence: -1,
        ),
        _secret,
      ),
      InternetAddress.loopbackIPv4,
      ackPort,
    );
    final boundBootstrap = await boundBootstrapFuture.timeout(
      const Duration(seconds: 2),
    );
    server.send(
      encodeSignedArmTeleopJson(
        _ack(
          sessionId: bridge.sessionId,
          bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sequence: boundBootstrap['seq']! as int,
          serviceState: 'HOLD',
        ),
        _secret,
      ),
      InternetAddress.loopbackIPv4,
      ackPort,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    frames.add(_frame(at: now, modeChanged: true));
    final armedFuture = controls.stream.firstWhere(
      (packet) => packet['arm_allowed'] == true,
    );
    frames.add(_frame(at: now, l1: true));
    final armed = await armedFuture.timeout(const Duration(seconds: 2));
    expect(bridge.armAllowed, isTrue);

    final revokedFuture = controls.stream.firstWhere(
      (packet) =>
          packet['arm_allowed'] == false &&
          packet['mode'] == 'arm' &&
          (packet['seq']! as int) > (armed['seq']! as int),
    );
    now = now.add(const Duration(milliseconds: 101));
    final revoked = await revokedFuture.timeout(const Duration(seconds: 2));

    expect(revoked['arm_allowed'], isFalse);
    expect(bridge.armAllowed, isFalse);
    expect(bridge.holdAckRequired, isTrue);

    await bridge.dispose();
    await frames.close();
    await serverSub.cancel();
    await controls.close();
    server.close();
  });

  test(
    'six-axis-only rejects schema/profile mismatch and never emits gripper commands',
    () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final ackPort = await _unusedUdpPort();
      final controls = StreamController<Map<String, Object?>>.broadcast();
      final serverSub = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = server.receive()) != null) {
          final decoded = decodeAndVerifyArmTeleopJson(datagram!.data, _secret);
          if (decoded != null) controls.add(decoded);
        }
      });
      final frames = StreamController<YunZhuoControlFrame>.broadcast(
        sync: true,
      );
      final bridge = ArmTeleopBridge(
        frames: frames.stream,
        dogStateProvider: () => 'Grounded',
        dogSafetyProvider: () => true,
        clock: DateTime.now,
        sessionId: '00112233445566778899aabbccddeeff',
        config: ArmTeleopBridgeConfig(
          remoteHost: '127.0.0.1',
          controlPort: server.port,
          ackPort: ackPort,
          secret: _secretText,
          activeProfile: armTeleopProfileSixAxisOnly,
          sendPeriod: const Duration(milliseconds: 5),
          ackTimeout: const Duration(seconds: 2),
          inputTimeout: const Duration(seconds: 2),
        ),
      );

      final discoveryFuture = controls.stream.first;
      await bridge.start();
      final discovery = await discoveryFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(discovery['v'], 2);
      expect(discovery['active_profile'], armTeleopProfileSixAxisOnly);
      expect(discovery['lt'], isFalse);
      expect(discovery['rt'], isFalse);

      final malformed = _ack(
        sessionId: '',
        bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: -1,
        activeProfile: armTeleopProfileSixAxisOnly,
      )..remove('gripper_feedback_fresh');
      server.send(
        encodeSignedArmTeleopJson(malformed, _secret),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(bridge.lastAck, isNull);
      expect(bridge.armAllowed, isFalse);

      final boundFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_boot_id'] == 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' &&
            packet['mode'] == 'neutral',
      );
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: '',
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: -1,
            activeProfile: armTeleopProfileSixAxisOnly,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      final bound = await boundFuture.timeout(const Duration(seconds: 2));

      // A signed full-gripper ACK cannot satisfy a six-axis-only request.
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: bound['seq']! as int,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      frames.add(_frame(at: DateTime.now(), modeChanged: true));
      frames.add(_frame(at: DateTime.now(), l1: true));
      expect(bridge.armAllowed, isFalse);

      final recoveryControl = await controls.stream
          .firstWhere(
            (packet) =>
                (packet['seq']! as int) > (bound['seq']! as int) &&
                packet['mode'] == 'arm' &&
                packet['arm_allowed'] == false,
          )
          .timeout(const Duration(seconds: 2));
      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: recoveryControl['seq']! as int,
            serviceState: 'HOLD',
            activeProfile: armTeleopProfileSixAxisOnly,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(bridge.lastAck?.healthy, isTrue);
      expect(bridge.holdAckRequired, isFalse);

      // Reset the rejected L1 edge through the normal neutral/arm gate before
      // attempting a fresh authorization.
      final neutralFuture = controls.stream.firstWhere(
        (packet) =>
            packet['mode'] == 'neutral' && packet['arm_allowed'] == false,
      );
      frames.add(
        _frame(
          at: DateTime.now(),
          mode: YunZhuoControlMode.neutral,
          modeChanged: true,
        ),
      );
      final firstNeutral = await neutralFuture.timeout(
        const Duration(seconds: 2),
      );
      final holdBarrier = bridge.holdAckBarrierSequence;
      if (holdBarrier != null) {
        final neutral = (firstNeutral['seq']! as int) >= holdBarrier
            ? firstNeutral
            : await controls.stream
                  .firstWhere(
                    (packet) =>
                        packet['mode'] == 'neutral' &&
                        packet['arm_allowed'] == false &&
                        (packet['seq']! as int) >= holdBarrier,
                  )
                  .timeout(const Duration(seconds: 2));
        server.send(
          encodeSignedArmTeleopJson(
            _ack(
              sessionId: bridge.sessionId,
              bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              sequence: neutral['seq']! as int,
              serviceState: 'HOLD',
              activeProfile: armTeleopProfileSixAxisOnly,
            ),
            _secret,
          ),
          InternetAddress.loopbackIPv4,
          ackPort,
        );
        await _waitUntil(() => !bridge.holdAckRequired);
      }
      expect(bridge.holdAckRequired, isFalse);

      frames.add(_frame(at: DateTime.now(), modeChanged: true));
      frames.add(_frame(at: DateTime.now()));
      final authorizedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true && packet['arm_request_id'] == 1,
      );
      frames.add(_frame(at: DateTime.now(), l1: true));
      final authorized = await authorizedFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(authorized['lt'], isFalse);
      expect(authorized['rt'], isFalse);

      server.send(
        encodeSignedArmTeleopJson(
          _ack(
            sessionId: bridge.sessionId,
            bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            sequence: authorized['seq']! as int,
            serviceState: 'ARMED',
            activeProfile: armTeleopProfileSixAxisOnly,
          ),
          _secret,
        ),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      try {
        await _waitUntil(
          () => bridge.lastAck?.serviceState == 'ARMED' && bridge.armAllowed,
        );
      } on TimeoutException {
        fail(
          'ARMED ACK was not accepted: authorizedSeq=${authorized['seq']} '
          'lastSeq=${bridge.lastAck?.sequence} '
          'lastState=${bridge.lastAck?.serviceState} '
          'lastProfile=${bridge.lastAck?.activeProfile} '
          'armAllowed=${bridge.armAllowed} ackFresh=${bridge.ackFresh} '
          'holdRequired=${bridge.holdAckRequired} '
          'holdBarrier=${bridge.holdAckBarrierSequence} '
          'transportFaulted=${bridge.transportFaulted}',
        );
      }

      final actionFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == true &&
            packet['lx_ppm'] == 250000 &&
            (packet['seq']! as int) > (authorized['seq']! as int),
      );
      frames.add(
        _frame(at: DateTime.now(), left: Vector2(0.25, 0), lt: true, rt: true),
      );
      final action = await actionFuture.timeout(const Duration(seconds: 2));
      expect(action['lt'], isFalse);
      expect(action['rt'], isFalse);

      final retransmit = await controls.stream
          .firstWhere(
            (packet) =>
                packet['arm_allowed'] == true &&
                (packet['seq']! as int) > (action['seq']! as int),
          )
          .timeout(const Duration(seconds: 2));
      expect(retransmit['lt'], isFalse);
      expect(retransmit['rt'], isFalse);

      final revokedFuture = controls.stream.firstWhere(
        (packet) =>
            packet['arm_allowed'] == false &&
            (packet['seq']! as int) > (retransmit['seq']! as int),
      );
      final unsafeDriver = _ack(
        sessionId: bridge.sessionId,
        bootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: retransmit['seq']! as int,
        serviceState: 'ARMED',
        activeProfile: armTeleopProfileSixAxisOnly,
      )..['gripper_driver_enabled'] = true;
      server.send(
        encodeSignedArmTeleopJson(unsafeDriver, _secret),
        InternetAddress.loopbackIPv4,
        ackPort,
      );
      final revoked = await revokedFuture.timeout(const Duration(seconds: 2));
      expect(bridge.armAllowed, isFalse);
      expect(bridge.lastAck, isNull);
      expect(revoked['active_profile'], armTeleopProfileSixAxisOnly);
      expect(revoked['lt'], isFalse);
      expect(revoked['rt'], isFalse);

      await bridge.dispose();
      await frames.close();
      await serverSub.cancel();
      await controls.close();
      server.close();
    },
  );
}
