import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

import 'arm_teleop_protocol.dart';
import 'yunzhuo_control_mode.dart';

final _log = Logger('han_dog.arm_teleop');

const Set<String> _knownArmServiceStates = <String>{
  'SAFE',
  'ARMING',
  'ARMED',
  'HOLD',
  'STOWING',
  'ESTOP',
  'FAULT',
};

bool _armL1Pressed(YunZhuoState state) =>
    state.rawChannels.length > 10 && state.rawChannels[10] == SbusValues.low;

// An absent or non-idle L2 channel fails closed and prevents L1 authorization.
bool _armL2Pressed(YunZhuoState state) =>
    state.rawChannels.length <= 6 || state.rawChannels[6] != SbusValues.high;

typedef DogStateProvider = String Function();
typedef DogSafetyProvider = bool Function();
typedef ArmPacketEncoder =
    Uint8List Function(ArmTeleopControlPacket packet, List<int> secret);
typedef ArmDatagramSender =
    int Function(
      RawDatagramSocket socket,
      Uint8List bytes,
      InternetAddress address,
      int port,
    );
typedef ArmDatagramReceiver = Datagram? Function(RawDatagramSocket socket);

/// 机器狗对机械臂模式的姿态/执行器联锁。
///
/// [Grounded] 是有防坠支撑、不允许底盘行走的安装联调路径：右前腿暂时
/// 缺少反馈时仍可操作机械臂。[Standing] 下机身必须依靠电机保持，因此
/// 16 路反馈和机器狗电机输出都必须正常。其他 FSM 状态始终拒绝。
bool isDogSafeForArmTeleop({
  required String dogState,
  required bool allActuatorFeedbackFresh,
  required bool motorOutputEnabled,
}) {
  if (dogState == 'Grounded') return true;
  return dogState == 'Standing' &&
      allActuatorFeedbackFresh &&
      motorOutputEnabled;
}

class ArmTeleopBridgeConfig {
  final String remoteHost;
  final int controlPort;
  final int ackPort;
  final String secret;
  final Duration sendPeriod;
  final Duration ackTimeout;
  final Duration inputTimeout;
  final Duration l2HoldDuration;
  final double stickDeadzone;
  final String activeProfile;

  const ArmTeleopBridgeConfig({
    this.remoteHost = '192.168.66.65',
    this.controlPort = 14600,
    this.ackPort = 14601,
    required this.secret,
    this.sendPeriod = const Duration(milliseconds: 20),
    this.ackTimeout = const Duration(milliseconds: 500),
    this.inputTimeout = const Duration(milliseconds: 150),
    this.l2HoldDuration = const Duration(milliseconds: 1500),
    this.stickDeadzone = 0.10,
    this.activeProfile = armTeleopProfileFullGripper,
  });

  bool get gripperControlEnabled =>
      activeProfile == armTeleopProfileFullGripper;

  void validate() {
    if (controlPort < 1 || controlPort > 65535) {
      throw ArgumentError.value(controlPort, 'controlPort');
    }
    if (ackPort < 1 || ackPort > 65535) {
      throw ArgumentError.value(ackPort, 'ackPort');
    }
    if (utf8.encode(secret).length < 32) {
      throw ArgumentError('Arm teleop HMAC secret must be at least 32 bytes');
    }
    final normalizedSecret = secret.toLowerCase();
    if (const <String>[
      'change-me',
      'changeme',
      'replace',
      'placeholder',
      'example',
    ].any(normalizedSecret.contains)) {
      throw ArgumentError('Arm teleop HMAC placeholder secret is forbidden');
    }
    if (sendPeriod <= Duration.zero ||
        ackTimeout <= Duration.zero ||
        inputTimeout <= Duration.zero) {
      throw ArgumentError('Arm teleop periods must be positive');
    }
    if (activeProfile != armTeleopProfileFullGripper &&
        activeProfile != armTeleopProfileSixAxisOnly) {
      throw ArgumentError.value(
        activeProfile,
        'activeProfile',
        'unsupported arm teleop profile',
      );
    }
  }
}

/// 云卓状态到机械臂 S100 的安全 UDP 桥接。
///
/// - 不读取串口，只消费 [RealController] 已解码并共享的控制帧。
/// - 50 Hz 周期发送，并在模式/按键安全事件发生时立即补发。
/// - 控制包与 ACK 都使用 canonical JSON + HMAC-SHA256。
/// - 新进程使用新 session_id，首包强制 neutral/arm_allowed=false。
class ArmTeleopBridge {
  final Stream<YunZhuoControlFrame> frames;
  final Stream<void>? hardStops;
  final DogStateProvider dogStateProvider;
  final DogSafetyProvider dogSafetyProvider;
  final ArmTeleopBridgeConfig config;
  final DateTime Function() _clock;
  final ArmPacketEncoder _packetEncoder;
  final ArmDatagramSender _datagramSender;
  final ArmDatagramReceiver _datagramReceiver;
  final String sessionId;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  StreamSubscription<YunZhuoControlFrame>? _frameSubscription;
  StreamSubscription<void>? _hardStopSubscription;
  Timer? _sendTimer;
  InternetAddress? _remoteAddress;
  YunZhuoControlFrame? _latestFrame;

  ArmTeleopAck? _lastAck;
  DateTime? _lastAckAt;
  int _lastAckSequence = -1;
  int _nextSequence = 0;
  String? _lastBootId;
  int _armRequestId = 0;
  int _stowRequestId = 0;
  int _estopRequestId = 0;
  int? _authorizationBarrierSequence;

  bool _armAllowed = false;
  bool _stowRequest = false;
  bool _estopLatched = false;
  bool _seenFrame = false;
  bool _inputTimedOut = false;
  bool _inputInterlock = false;
  bool _interlockSawNeutral = false;
  bool _wasArmMode = false;
  bool _lastL1Pressed = false;
  bool _lastL2Pressed = false;
  bool _lastRed = false;
  bool _l2Ready = false;
  bool _ltReady = false;
  bool _rtReady = false;
  DateTime? _l2PressedAt;
  bool _l2LongTriggered = false;
  bool _started = false;
  bool _disposed = false;
  bool _transportFaulted = false;
  bool _receiveFaulted = false;
  bool _holdAckRequired = false;
  int? _holdAckBarrierSequence;
  DateTime? _lastTransportErrorLogAt;

  ArmTeleopBridge({
    required this.frames,
    this.hardStops,
    required this.dogStateProvider,
    required this.dogSafetyProvider,
    required this.config,
    DateTime Function()? clock,
    ArmPacketEncoder? packetEncoder,
    ArmDatagramSender? datagramSender,
    ArmDatagramReceiver? datagramReceiver,
    String? sessionId,
  }) : _clock = clock ?? processMonotonicNow,
       _packetEncoder = packetEncoder ?? _defaultPacketEncoder,
       _datagramSender = datagramSender ?? _defaultDatagramSender,
       _datagramReceiver = datagramReceiver ?? _defaultDatagramReceiver,
       sessionId = sessionId ?? newArmTeleopSessionId();

  ArmTeleopAck? get lastAck => _lastAck;
  bool get armAllowed => _armAllowed;
  bool get estopLatched => _estopLatched;
  bool get transportFaulted => _transportFaulted || _receiveFaulted;
  bool get holdAckRequired => _holdAckRequired;
  int? get holdAckBarrierSequence => _holdAckBarrierSequence;

  bool get ackFresh {
    final at = _lastAckAt;
    if (at == null) return false;
    final age = _clock().difference(at);
    return !age.isNegative && age <= config.ackTimeout;
  }

  Future<void> start() async {
    if (_disposed) throw StateError('ArmTeleopBridge is disposed');
    if (_started) return;
    config.validate();

    final addresses = await InternetAddress.lookup(
      config.remoteHost,
      type: InternetAddressType.IPv4,
    );
    if (addresses.isEmpty) {
      throw SocketException('Cannot resolve arm host ${config.remoteHost}');
    }
    _remoteAddress = addresses.first;
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      config.ackPort,
      reuseAddress: true,
    );
    _socketSubscription = _socket!.listen(
      _onSocketEvent,
      onError: (Object error, StackTrace stackTrace) {
        _handleReceiveFailure(error, stackTrace);
      },
    );

    _frameSubscription = frames.listen(
      _onFrame,
      onError: (Object error, StackTrace stackTrace) {
        _log.warning('Arm input stream error', error, stackTrace);
        _handleInputLoss('controller stream error');
      },
      onDone: () => _handleInputLoss('controller stream closed'),
    );
    _hardStopSubscription = hardStops?.listen(
      (_) => _handleInputLoss('controller hard stop'),
      onError: (Object error, StackTrace stackTrace) =>
          _handleInputLoss('hard stop stream error: $error'),
      onDone: () => _handleInputLoss('hard stop stream closed'),
    );
    _sendTimer = Timer.periodic(config.sendPeriod, (_) => _onPeriodicSend());
    _started = true;

    // 新 session 的第一包永远是安全中立包，远端据此建立新的序列窗口。
    _sendPacket(forceBootstrapSafe: true);
    _log.info(
      'Arm bridge started: ${_remoteAddress!.address}:${config.controlPort}, '
      'ack=0.0.0.0:${config.ackPort}, session=$sessionId',
    );
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _disposed) return;
    final socket = _socket;
    if (socket == null) return;
    try {
      // 单次事件限制 drain 数量，避免无效 UDP 洪泛饿死遥控器看门狗。
      for (var drained = 0; drained < 64; drained++) {
        final packet = _datagramReceiver(socket);
        if (packet == null) break;
        if (packet.address.address != _remoteAddress?.address ||
            packet.port != config.controlPort) {
          _log.fine(
            'Ignored arm ACK from unexpected '
            '${packet.address.address}:${packet.port}',
          );
          continue;
        }
        final verifiedAck = decodeAndVerifyArmTeleopJson(
          packet.data,
          utf8.encode(config.secret),
        );
        if (verifiedAck == null) {
          _log.fine('Ignored unauthenticated arm ACK');
          continue;
        }
        final ack = ArmTeleopAck.fromVerifiedJson(verifiedAck);
        if (ack == null) {
          _invalidateAuthenticatedAck(
            'authenticated ACK has missing, extra, or invalid v2 fields',
          );
          continue;
        }
        _receiveFaulted = false;
        final remoteRestarted = _lastBootId != ack.bootId;
        _lastBootId = ack.bootId;
        if (remoteRestarted) _handleRemoteRestart();

        if (!ack.matchesRequestedProfile(config.activeProfile)) {
          _invalidateAuthenticatedAck(
            'remote profile/capability mismatch: requested='
            '${config.activeProfile}, remote=${ack.activeProfile}, '
            'capabilities=${ack.capabilities}',
          );
          continue;
        }
        if (config.activeProfile == armTeleopProfileSixAxisOnly &&
            (ack.gripperControlEnabled ||
                ack.gripperAvailable ||
                ack.gripperDriverEnabled != false ||
                ack.gripperOk)) {
          _invalidateAuthenticatedAck(
            'six-axis-only ACK did not prove disabled gripper state',
          );
          continue;
        }

        // S100 尚未接受新 session 时会以 session_id="", seq=-1 回签 SAFE。
        // 该包只用于发现 boot_id，不能刷新健康/新鲜度。
        if (ack.sessionId != sessionId) continue;
        if (ack.sequence <= _lastAckSequence || ack.sequence >= _nextSequence) {
          _log.warning(
            'Ignored stale/impossible arm ACK seq=${ack.sequence} '
            '(last=$_lastAckSequence, next=$_nextSequence)',
          );
          continue;
        }
        _lastAck = ack;
        _lastAckAt = _clock();
        _lastAckSequence = ack.sequence;
        _clearHoldAckIfSatisfied(ack);
        final authorizationBarrier = _authorizationBarrierSequence;
        if (_armAllowed &&
            authorizationBarrier != null &&
            ack.sequence < authorizationBarrier) {
          // L1 授权包之前已在网络中的旧 ACK 只更新链路新鲜度。
          // 它不能拒绝还未被远端观察到的新授权，也不能放行动作。
          continue;
        }
        if (!_knownArmServiceStates.contains(ack.serviceState)) {
          _revokeMotion('remote returned unknown state ${ack.serviceState}');
        } else if (!ack.healthy ||
            ack.serviceState == 'FAULT' ||
            ack.serviceState == 'ESTOP') {
          _revokeMotion(
            'remote ${ack.serviceState}: ${ack.fault ?? "unhealthy"}',
          );
        } else if ((ack.serviceState == 'SAFE' || ack.serviceState == 'HOLD') &&
            _armAllowed) {
          // ARMING/ARMED/STOWING 是授权后唯一允许持续的远端状态。
          // SAFE/HOLD 表示远端拒绝、看门狗保持或动作已结束，必须
          // 先观察到 false 回执，再由一次新 L1 重新授权。
          _revokeMotion(
            'remote ${ack.serviceState} requires fresh L1 authorization',
          );
        }
      }
    } on Object catch (error, stackTrace) {
      _handleReceiveFailure(error, stackTrace);
    }
  }

  void _handleReceiveFailure(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _receiveFaulted = true;
    _requireHoldAck();
    _armAllowed = false;
    _stowRequest = false;
    _logTransportFailureThrottled(
      'Arm UDP receive failed; arm permission revoked',
      error,
      stackTrace,
    );
    if (_started) _sendPacket(forceBootstrapSafe: true);
  }

  void _invalidateAuthenticatedAck(String reason) {
    final motionWasActive = _armAllowed || _stowRequest;
    _requireHoldAck();
    _armAllowed = false;
    _stowRequest = false;
    _lastAck = null;
    _lastAckAt = null;
    _log.warning('Arm ACK rejected; permission revoked: $reason');
    if (motionWasActive && _started && !_disposed) {
      _sendPacket(forceBootstrapSafe: true);
    }
  }

  void _handleRemoteRestart() {
    _requireHoldAck();
    _armAllowed = false;
    _stowRequest = false;
    _lastAck = null;
    _lastAckAt = null;
    _wasArmMode = false;
    _l2PressedAt = null;
    _l2LongTriggered = false;
    _l2Ready = false;
    _ltReady = false;
    _rtReady = false;
    _log.warning('Arm service boot_id changed; restarting safe handshake');
    // 同一 sender session 保持递增 seq，但先用 neutral 安全包建立远端新窗口。
    _sendPacket(forceBootstrapSafe: true);
  }

  void _onFrame(YunZhuoControlFrame frame) {
    if (_disposed) return;
    final state = frame.state;
    // H20/R20 shoulder push-buttons are active-low on the live SBUS link:
    // released=1722, pressed=282. Keep this arm-only interpretation separate
    // from the legacy dog button stream, whose double-edge behavior is part of
    // the existing machine-dog contract.
    final l1Pressed = _armL1Pressed(state);
    final l2Pressed = _armL2Pressed(state);
    _inputTimedOut = false;
    final reportedArmMode = frame.mode.mode == YunZhuoControlMode.arm;
    if (_inputInterlock) {
      if (frame.mode.mode == YunZhuoControlMode.neutral) {
        _interlockSawNeutral = true;
      } else if (_interlockSawNeutral && reportedArmMode) {
        _inputInterlock = false;
        _interlockSawNeutral = false;
        _wasArmMode = false;
        _log.info(
          'Controller input interlock cleared after neutral mode cycle',
        );
      }
    }
    final isArmMode = reportedArmMode && !_inputInterlock;
    var immediate = frame.mode.modeChanged;

    final redRising = state.red && (!_seenFrame || !_lastRed);
    if (redRising) {
      _requireHoldAck();
      _estopRequestId++;
      _estopLatched = true;
      _armAllowed = false;
      _stowRequest = false;
      immediate = true;
      _log.severe('Arm ESTOP requested by red button');
    }

    if (!isArmMode) {
      if (_wasArmMode) _requireHoldAck();
      if (_wasArmMode || _armAllowed || _stowRequest) immediate = true;
      _armAllowed = false;
      _stowRequest = false;
      _l2PressedAt = null;
      _l2LongTriggered = false;
      _l2Ready = false;
      _ltReady = false;
      _rtReady = false;
    } else if (!_wasArmMode) {
      // 进入 arm 时采样按键基线，要求释放后重新按下，避免带键切档。
      _armAllowed = false;
      _stowRequest = false;
      _lastL1Pressed = l1Pressed;
      _lastL2Pressed = l2Pressed;
      _l2PressedAt = null;
      _l2LongTriggered = false;
      _l2Ready = !l2Pressed;
      _ltReady = !state.LT;
      _rtReady = !state.RT;
      immediate = true;
    } else {
      if (!state.LT) _ltReady = true;
      if (!state.RT) _rtReady = true;
      final l1Rising = l1Pressed && !_lastL1Pressed;
      final l2WasReady = _l2Ready;
      if (!_l2Ready && !l2Pressed) _l2Ready = true;
      final l2Rising = l2WasReady && l2Pressed && !_lastL2Pressed;
      final l2Falling = l2WasReady && !l2Pressed && _lastL2Pressed;

      if (l1Rising) {
        if (_armAllowed) {
          // ARMING/ARMED/STOWING 期间的重复 L1 不是新授权。忽略它，
          // 避免在 enable 进行中先撤权再触发远端电子急停。
          _log.fine('Ignored duplicate L1 while arm authorization is active');
        } else if (_canGrantMotion(frame)) {
          _armRequestId++;
          _armAllowed = true;
          _authorizationBarrierSequence = null;
          _log.info('L1 → arm motion permission granted');
        } else {
          if (_armAllowed || _stowRequest) _requireHoldAck();
          _armAllowed = false;
          _log.warning('L1 arm request rejected by safety preconditions');
        }
        immediate = true;
      }
      if (l2Rising) {
        _l2PressedAt = frame.receivedAt;
        _l2LongTriggered = false;
        immediate = true;
      }
      if (l2Falling) {
        if (!_l2LongTriggered) {
          _requireHoldAck();
          _armAllowed = false;
          _log.info('L2 short press → arm HOLD');
        }
        _stowRequest = false;
        _l2PressedAt = null;
        _l2LongTriggered = false;
        immediate = true;
      }
    }

    _latestFrame = frame;
    _seenFrame = true;
    _wasArmMode = isArmMode;
    _lastL1Pressed = l1Pressed;
    _lastL2Pressed = l2Pressed;
    _lastRed = state.red;
    if (immediate && _started) _sendPacket();
  }

  void _onPeriodicSend() {
    if (_disposed || !_started) return;
    final frame = _latestFrame;
    if (frame != null && !_inputTimedOut) {
      final frameAge = _clock().difference(frame.receivedAt);
      if (frameAge.isNegative || frameAge >= config.inputTimeout) {
        _handleInputLoss(
          frameAge.isNegative
              ? 'controller clock moved backwards'
              : 'controller frame timeout',
        );
      }
    }
    if (_armAllowed && (frame == null || !_canContinueMotion(frame))) {
      _revokeMotion('safety precondition lost');
    }

    if (frame != null &&
        frame.mode.mode == YunZhuoControlMode.arm &&
        _armL2Pressed(frame.state) &&
        !_l2LongTriggered &&
        _l2PressedAt != null &&
        frame.receivedAt.difference(_l2PressedAt!) >= config.l2HoldDuration) {
      _l2LongTriggered = true;
      if (_armAllowed &&
          _remoteReadyForActions &&
          areYunZhuoSticksCentered(frame.state, config.stickDeadzone) &&
          _isDogStable() &&
          _isDogSafe()) {
        _stowRequestId++;
        _stowRequest = true;
        _log.info('L2 long press → stow request');
      } else {
        _requireHoldAck();
        _armAllowed = false;
        _stowRequest = false;
        _log.warning('L2 stow rejected; arm moved to HOLD');
      }
    }
    _sendPacket();
  }

  bool _canGrantMotion(YunZhuoControlFrame frame) =>
      !_estopLatched &&
      !_inputInterlock &&
      frame.mode.mode == YunZhuoControlMode.arm &&
      areYunZhuoSticksCentered(frame.state, config.stickDeadzone) &&
      !_armL2Pressed(frame.state) &&
      (!config.gripperControlEnabled || (!frame.state.LT && !frame.state.RT)) &&
      _isDogStable() &&
      _isDogSafe() &&
      ackFresh &&
      (_lastAck?.healthy ?? false) &&
      (_lastAck?.matchesRequestedProfile(config.activeProfile) ?? false) &&
      (_lastAck?.serviceState == 'SAFE' || _lastAck?.serviceState == 'HOLD') &&
      !_holdAckRequired &&
      !transportFaulted;

  bool _canContinueMotion(YunZhuoControlFrame frame) {
    if (_estopLatched ||
        _inputInterlock ||
        frame.mode.mode != YunZhuoControlMode.arm ||
        !_isDogStable() ||
        !_isDogSafe() ||
        !ackFresh ||
        transportFaulted) {
      return false;
    }
    final ack = _lastAck;
    final barrier = _authorizationBarrierSequence;
    if (ack == null || barrier == null) return false;
    if (ack.sequence < barrier) {
      // 旧 ACK 不影响新授权；等待覆盖 barrier 的 ACK，超时则撤权。
      return true;
    }
    return ack.healthy &&
        ack.matchesRequestedProfile(config.activeProfile) &&
        _knownArmServiceStates.contains(ack.serviceState) &&
        ack.serviceState != 'FAULT' &&
        ack.serviceState != 'ESTOP';
  }

  /// 协议授权与动作转发分离：L1 后 arm_allowed 在 ARMING 期间
  /// 必须保持 true，但只有新鲜、健康的 ARMED 回执才可放行摇杆与夹爪。
  bool get _remoteReadyForActions =>
      ackFresh &&
      (_lastAck?.healthy ?? false) &&
      (_lastAck?.matchesRequestedProfile(config.activeProfile) ?? false) &&
      _lastAck?.serviceState == 'ARMED' &&
      _authorizationBarrierSequence != null &&
      _lastAck!.sequence >= _authorizationBarrierSequence! &&
      !transportFaulted;

  bool _isDogStable() {
    try {
      final state = dogStateProvider();
      return state == 'Standing' || state == 'Grounded';
    } on Object {
      return false;
    }
  }

  bool _isDogSafe() {
    try {
      return dogSafetyProvider();
    } on Object {
      return false;
    }
  }

  String _dogState() {
    try {
      return dogStateProvider();
    } on Object {
      return 'Unknown';
    }
  }

  bool _requireHoldAck({int? sequence}) {
    final newlyRequired = !_holdAckRequired;
    if (newlyRequired) {
      _holdAckRequired = true;
      _holdAckBarrierSequence = null;
    }
    if (_holdAckBarrierSequence == null && sequence != null) {
      _holdAckBarrierSequence = sequence;
    }
    return newlyRequired;
  }

  void _clearHoldAckIfSatisfied(ArmTeleopAck ack) {
    final barrier = _holdAckBarrierSequence;
    if (!_holdAckRequired || barrier == null || ack.sequence < barrier) return;
    if (ack.serviceState != 'SAFE' && ack.serviceState != 'HOLD') return;
    _holdAckRequired = false;
    _holdAckBarrierSequence = null;
    _log.info('Remote HOLD acknowledged at seq=${ack.sequence}');
  }

  void _revokeMotion(String reason) {
    final changed = _armAllowed || _stowRequest;
    if (!changed) {
      // 已经没有本地授权时，持续的远端 SAFE/FAULT 不会产生新的动作。
      // 不要为同一个预存异常反复建立、清除 HOLD ACK 握手；未来 L1
      // 仍会被不健康回执挡住。真正处于授权/收纳中时则继续走下方撤权。
      return;
    }
    _requireHoldAck();
    _armAllowed = false;
    _stowRequest = false;
    _log.warning('Arm motion permission revoked: $reason');
    if (_started && !_disposed) _sendPacket();
  }

  void _handleInputLoss(String reason) {
    if (_disposed) return;
    _requireHoldAck();
    final firstLoss = !_inputTimedOut;
    _inputTimedOut = true;
    _inputInterlock = true;
    _interlockSawNeutral = false;
    _armAllowed = false;
    _stowRequest = false;
    _wasArmMode = false;
    _l2PressedAt = null;
    _l2LongTriggered = false;
    _l2Ready = false;
    _ltReady = false;
    _rtReady = false;
    if (firstLoss) _log.warning('Arm input interlocked: $reason');
    if (_started) _sendPacket(forceBootstrapSafe: true);
  }

  bool _sendPacket({bool forceBootstrapSafe = false}) {
    final socket = _socket;
    final remoteAddress = _remoteAddress;
    if (socket == null || remoteAddress == null || _disposed) return false;

    int? attemptedSequence;
    try {
      final frame = _latestFrame;
      final discoveringBoot = _lastBootId == null;
      final forceSafe = forceBootstrapSafe || discoveringBoot;
      final isArm =
          !forceSafe &&
          !_inputInterlock &&
          frame?.mode.mode == YunZhuoControlMode.arm;
      final motionAuthorized =
          isArm && _armAllowed && !_estopLatched && !_holdAckRequired;
      final actionsAllowed =
          motionAuthorized && _remoteReadyForActions && !_stowRequest;
      final state = frame?.state;
      attemptedSequence = _nextSequence++;
      if (motionAuthorized && _authorizationBarrierSequence == null) {
        _authorizationBarrierSequence = attemptedSequence;
      }
      if (_holdAckRequired &&
          _holdAckBarrierSequence == null &&
          !motionAuthorized) {
        _holdAckBarrierSequence = attemptedSequence;
      }
      final packet = ArmTeleopControlPacket(
        sessionId: sessionId,
        armBootId: _lastBootId ?? '',
        sequence: attemptedSequence,
        mode: forceSafe
            ? YunZhuoControlMode.neutral.name
            : (frame?.mode.mode.name ?? YunZhuoControlMode.neutral.name),
        activeProfile: config.activeProfile,
        armAllowed: motionAuthorized,
        stowRequest: motionAuthorized && _stowRequest,
        estop: _estopLatched,
        dogState: _dogState(),
        lx: actionsAllowed ? state!.leftStick.x : 0.0,
        ly: actionsAllowed ? state!.leftStick.y : 0.0,
        rx: actionsAllowed ? state!.rightStick.x : 0.0,
        ry: actionsAllowed ? state!.rightStick.y : 0.0,
        lt:
            config.gripperControlEnabled &&
            actionsAllowed &&
            _ltReady &&
            state!.LT,
        rt:
            config.gripperControlEnabled &&
            actionsAllowed &&
            _rtReady &&
            state!.RT,
        armRequestId: _armRequestId,
        stowRequestId: _stowRequestId,
        estopRequestId: _estopRequestId,
      );
      final bytes = _packetEncoder(packet, utf8.encode(config.secret));
      final sent = _datagramSender(
        socket,
        bytes,
        remoteAddress,
        config.controlPort,
      );
      if (sent != bytes.length) {
        throw SocketException('short UDP send: $sent/${bytes.length} bytes');
      }
      _transportFaulted = false;
      return true;
    } on Object catch (error, stackTrace) {
      // 机械臂网络/编码故障绝不能越过桥边界杀死 han_dog 主进程。
      _requireHoldAck(sequence: attemptedSequence);
      _armAllowed = false;
      _stowRequest = false;
      _transportFaulted = true;
      _logTransportFailureThrottled(
        'Arm UDP send failed; arm permission revoked',
        error,
        stackTrace,
      );
      return false;
    }
  }

  void _logTransportFailureThrottled(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    final now = _clock();
    final last = _lastTransportErrorLogAt;
    if (last != null &&
        !now.difference(last).isNegative &&
        now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastTransportErrorLogAt = now;
    try {
      _log.warning(message, error, stackTrace);
    } on Object {
      // 日志订阅器异常也不能越过机械臂桥边界。
    }
  }

  static Uint8List _defaultPacketEncoder(
    ArmTeleopControlPacket packet,
    List<int> secret,
  ) => packet.encode(secret);

  static int _defaultDatagramSender(
    RawDatagramSocket socket,
    Uint8List bytes,
    InternetAddress address,
    int port,
  ) => socket.send(bytes, address, port);

  static Datagram? _defaultDatagramReceiver(RawDatagramSocket socket) =>
      socket.receive();

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      if (_started) {
        _armAllowed = false;
        _stowRequest = false;
        _sendPacket(forceBootstrapSafe: true); // best effort; never throws
      }
    } finally {
      _disposed = true;
      _sendTimer?.cancel();
      for (final subscription in <StreamSubscription<Object?>?>[
        _frameSubscription,
        _hardStopSubscription,
        _socketSubscription,
      ]) {
        try {
          await subscription?.cancel();
        } on Object catch (error, stackTrace) {
          _log.fine('Arm bridge subscription cancel failed', error, stackTrace);
        }
      }
      try {
        _socket?.close();
      } on Object catch (error, stackTrace) {
        _log.fine('Arm bridge socket close failed', error, stackTrace);
      }
      _socket = null;
      _started = false;
      _log.info('Arm bridge disposed');
    }
  }
}
