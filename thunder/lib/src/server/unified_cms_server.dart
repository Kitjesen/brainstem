import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:logging/logging.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import '../app/profile_manager.dart';
import '../control_arbiter.dart';
import '../control_lease.dart';
import '../real_joint.dart';
import 'gain_manager.dart';
import 'grpc_lan_development.dart';
import 'proto_convert.dart';
import '../recovery/normal_recovery_runtime.dart';
import 'recovery_service.dart';

final _log = Logger('thunder.server');

Map<String, List<int>> _validatedMotionPrincipals(
  Map<String, List<int>> principals,
) {
  if (principals.length > 16) {
    throw ArgumentError.value(principals.length, 'principals', 'maximum is 16');
  }
  final validated = <String, List<int>>{};
  for (final entry in principals.entries) {
    if (entry.key.isEmpty || entry.key.trim() != entry.key) {
      throw ArgumentError.value(
        entry.key,
        'principal',
        'must be non-empty and trimmed',
      );
    }
    if (entry.value.isEmpty ||
        entry.value.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(
        entry.key,
        'principal',
        'certificate DER must contain bytes',
      );
    }
    for (final existing in validated.entries) {
      if (_sameCertificate(existing.value, entry.value)) {
        throw ArgumentError(
          'principals ${existing.key} and ${entry.key} use the same certificate',
        );
      }
    }
    validated[entry.key] = List<int>.unmodifiable(entry.value);
  }
  return Map<String, List<int>>.unmodifiable(validated);
}

bool _sameCertificate(List<int> left, List<int> right) {
  if (left.length != right.length || left.isEmpty) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

/// 运行模式。
enum CmsMode {
  /// 纯仿真: Tick/Step 由外部驱动（MuJoCo），无 ControlArbiter。
  simulation,

  /// 真实硬件: 50Hz Timer 驱动，有 ControlArbiter。
  hardware,
}

/// 统一 gRPC 服务，取代原来的 CmsServer / SimDogServer / RealDogServer。
///
/// 通过 [CmsMode] 和可选依赖注入控制行为：
///
/// | 参数 | simulation | hardware |
/// |------|-----------|----------|
/// | [arbiter] | null | 必须 |
/// | [simInjector] | 必须 | null |
/// | [motor] | 可选 | 可选 |
/// | [gains] | 推荐 | 推荐 |
/// | [imuStreamFactory] | null (clock 驱动) | 必须 |
/// | [jointStreamFactory] | null (clock 驱动) | 必须 |
class UnifiedCmsServer extends proto.RobotControlServiceBase {
  final Brain _brain;
  final M _m;
  final CmsMode mode;
  final ControlArbiter? arbiter;
  final SimStateInjector? simInjector;
  final MotorService? motor;
  final GainManager? gains;
  final proto.RobotType robotType;
  final Duration grpcLeaseTimeout;
  final Set<String> hardwareMotionPeerAddresses;
  final bool developmentPlaintext;
  final Map<String, List<int>> hardwareMotionPrincipals;

  late final GrpcControlLease _grpcLease;
  StreamSubscription<ControlSource?>? _ownerSubscription;
  String _leaseOwnerId = '';
  proto.CommandRejectReason _lastControlDecision =
      proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE;
  proto.WalkRequest? _lastAcceptedWalk;
  bool _initialZeroAcknowledged = false;
  bool _grpcMotionIssued = false;
  var _acceptedControlCommands = proto.ControlStatus().acceptedCount;
  var _rejectedControlCommands = proto.ControlStatus().rejectedCount;

  /// Authoritative runtime state owned by the hardware process.
  bool Function()? motorOutputEnabledProvider;
  bool Function()? criticalMotorFaultProvider;
  bool Function()? externalMotorEnablePendingProvider;
  Object? Function()? externalProfileContextProvider;
  int _motorEnablePending = 0;
  bool get motorEnablePending => _motorEnablePending > 0;

  /// 策略管理器（可选，由外部注入）。
  ProfileManager? profileManager;

  /// Joint controller for calibration.
  RealJoint? joint;

  /// Walk rate limiting.
  Duration? _lastWalkAt;
  static const _minWalkInterval = Duration(milliseconds: 18);
  static const _walkStopEpsilon = 0.001;
  double _lastWalkX = 0.0;
  double _lastWalkY = 0.0;
  double _lastWalkZ = 0.0;

  /// SetZero lock.
  bool _zeroing = false;
  bool get calibrationPending => _zeroing;
  bool _disposed = false;
  int _profileContextVersion = 0;

  /// 硬件模式：由外部提供 IMU 数据流。
  final Stream<proto.Imu> Function()? imuStreamFactory;

  /// 硬件模式：由外部提供关节数据流。
  final Stream<proto.Joint> Function()? jointStreamFactory;

  final DateTime _startTime = DateTime.now();
  final Stopwatch _monotonicClock = Stopwatch()..start();

  /// 最近一次运动命令（walk/standUp/sitDown）的时间戳。
  DateTime? _lastCommandAt;
  DateTime? get lastCommandAt => _lastCommandAt;

  static const _enableJointLimitRad = 3.14;
  static const _enableJointNames = [
    'FR Hip',
    'FR Thigh',
    'FR Calf',
    'FL Hip',
    'FL Thigh',
    'FL Calf',
    'RR Hip',
    'RR Thigh',
    'RR Calf',
    'RL Hip',
    'RL Thigh',
    'RL Calf',
    'FR Foot',
    'FL Foot',
    'RR Foot',
    'RL Foot',
  ];

  /// 仿真模式 listenImu 用的默认四元数。
  static final _identityQ = Quaternion.identity();

  /// 广播流缓存：支持多客户端。
  late final _historyBroadcast = _brain.historyStream.asBroadcastStream();

  UnifiedCmsServer({
    required Brain brain,
    required M m,
    this.mode = CmsMode.simulation,
    this.arbiter,
    this.simInjector,
    this.motor,
    this.gains,
    this.robotType = proto.RobotType.MINI,
    this.grpcLeaseTimeout = const Duration(milliseconds: 300),
    Set<String> hardwareMotionPeerAddresses = const <String>{},
    this.developmentPlaintext = false,
    Map<String, List<int>> hardwareMotionPrincipals = const {},
    this.imuStreamFactory,
    this.jointStreamFactory,
  }) : _brain = brain,
       _m = m,
       hardwareMotionPeerAddresses = Set<String>.unmodifiable(
         hardwareMotionPeerAddresses,
       ),
       hardwareMotionPrincipals = _validatedMotionPrincipals(
         hardwareMotionPrincipals,
       ) {
    _grpcLease = GrpcControlLease(
      timeout: grpcLeaseTimeout,
      onExpired: _onGrpcLeaseExpired,
    );
    _ownerSubscription = arbiter?.ownerStream.listen(
      _onControlOwnerChanged,
      onError: (Object error, StackTrace stackTrace) {
        _log.severe('Control owner stream failed', error, stackTrace);
      },
    );
  }

  proto.Duration _elapsed() => proto.Duration.fromDart(_monotonicClock.elapsed);

  // ═══════════════════════════════════════════════════════════
  //  生命周期
  // ═══════════════════════════════════════════════════════════

  /// Hardware boot/read-only policy must run before any actuator enable.
  String? Function()? motorEnableBlockReason;

  /// gRPC Enable/Disable 时的回调（无遥控器时用于设置 motorOutputEnabled）。
  void Function(bool enabled)? onMotorEnableChanged;

  NormalRecoveryRuntime? recovery;

  RecoveryService get recoveryService => RecoveryService(recovery, (call) {
    final principal = _motionCallerPrincipal(call);
    if (principal == null) {
      throw GrpcError.permissionDenied(
        'Recovery caller is not authorized',
      );
    }
    return principal;
  });

  @override
  Future<proto.Empty> enable(ServiceCall call, proto.Empty request) async {
    _requireActuatorCaller(call);
    if (motorEnablePending) {
      throw GrpcError.failedPrecondition('Motor enable already in progress');
    }
    _profileContextVersion++;
    arbiter?.markSafetyChange();
    final blockReason = _enableBlockReason();
    if (blockReason != null) {
      _log.warning('Motors enable blocked: $blockReason');
      throw GrpcError.failedPrecondition('Motors enable blocked: $blockReason');
    }
    final epoch = _profileContextVersion;
    final ownerContext = arbiter?.contextVersion;
    _motorEnablePending++;
    try {
      await motor?.enable();
      if (_disposed ||
          epoch != _profileContextVersion ||
          arbiter?.contextVersion != ownerContext ||
          profileManager?.hasFault == true) {
        onMotorEnableChanged?.call(false);
        await motor?.disable();
        throw GrpcError.failedPrecondition('Motor enable was superseded');
      }
      onMotorEnableChanged?.call(true);
    } on StateError catch (error) {
      onMotorEnableChanged?.call(false);
      throw GrpcError.failedPrecondition(error.message);
    } finally {
      _motorEnablePending--;
    }
    _log.info('Motors enabled');
    return proto.Empty();
  }

  @override
  Future<proto.Empty> disable(ServiceCall call, proto.Empty request) async {
    _requireActuatorCaller(call, allowRecoveryStop: true);
    recovery?.interrupt('Operator disabled motors');
    _profileContextVersion++;
    arbiter?.markSafetyChange();
    _revokeGrpcControl(
      proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTORS_DISABLED,
    );
    onMotorEnableChanged?.call(false);
    await motor?.disable();
    if (motor case RealJoint j when !j.lastDisableConfirmed) {
      throw GrpcError.unavailable(
        'Motor disable unconfirmed: ${j.unconfirmedDisableJoints}',
      );
    }
    _log.info('Motors disabled');
    return proto.Empty();
  }

  String? _enableBlockReason() {
    if (_zeroing) return 'Joint calibration is still in progress';
    if (profileManager?.hasFault == true) {
      return 'profile state is inconsistent';
    }
    if (externalMotorEnablePendingProvider?.call() == true) {
      return 'Motor enable already in progress';
    }
    final externalReason = motorEnableBlockReason?.call();
    if (externalReason != null) return externalReason;
    if (mode != CmsMode.hardware) return null;
    final j = joint;
    if (j == null) return 'joint controller unavailable';

    final offline = <String>[];
    final unsafe = <String>[];
    for (var i = 0; i < _enableJointNames.length; i++) {
      final name = _enableJointNames[i];
      if (!j.isOnline(i)) {
        offline.add(name);
        continue;
      }
      final report = j.getReport(i);
      if (report == null) {
        offline.add(name);
        continue;
      }

      final status = report.status.value;
      if (status == 1 || status == 3) {
        unsafe.add('$name status=${report.status}');
      }
      if (report.errors.errors.isNotEmpty) {
        unsafe.add('$name errors=${report.errors.errors.join(",")}');
      }
      if (i < 12) {
        final position = report.position;
        if (!position.isFinite || position.abs() > _enableJointLimitRad) {
          unsafe.add('$name position=${position.toStringAsFixed(3)}rad');
        }
      }
      if (!report.velocity.isFinite || !report.torque.isFinite) {
        unsafe.add('$name non-finite velocity/torque');
      }
    }

    if (offline.isNotEmpty) return 'offline joints: ${offline.join(", ")}';
    if (unsafe.isNotEmpty) return 'unsafe joints: ${unsafe.join("; ")}';
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  //  运动指令（有 arbiter → 仲裁，无 arbiter → 直接操作 M）
  // ═══════════════════════════════════════════════════════════

  bool _dispatch(A action) {
    final now = DateTime.now();
    final sinceMs = _lastCommandAt != null
        ? now.difference(_lastCommandAt!).inMilliseconds
        : null;
    _lastCommandAt = now;

    final a = arbiter;
    if (a != null) {
      if (!a.command(action, ControlSource.grpc)) {
        _log.warning(
          '${action.runtimeType} rejected: ${a.owner} has priority'
          '${sinceMs != null ? " (${sinceMs}ms since last cmd)" : ""}',
        );
        return false; // 静默忽略，不抛异常
      }
    } else {
      _m.add(action);
    }
    _log.finest(
      '${action.runtimeType} dispatched'
      '${sinceMs != null ? " (${sinceMs}ms since last cmd)" : ""}',
    );
    gains?.applyCommand(action);
    return true;
  }

  // Body-frame SI limits. Values are rejected, never normalized or rescaled.
  static const _maxLinearMps = 3.0;
  static const _maxYawRps = 3.0;
  static const _localGrpcPrincipal = 'local-grpc@bsrl1';
  static const _localRcPrincipal = 'local-rc@bsrl1';

  @override
  Future<proto.Empty> walk(ServiceCall call, proto.Vector3 request) async {
    if (mode == CmsMode.hardware) {
      _log.warning(
        'Legacy Walk rejected in hardware mode; use lease-aware WalkChecked',
      );
      throw GrpcError.unimplemented(
        'Legacy Walk is disabled in hardware mode; use WalkChecked',
      );
    }
    final now = _monotonicClock.elapsed;
    if (_lastWalkAt != null && now - _lastWalkAt! < _minWalkInterval) {
      // 频率过高：静默忽略而非报错，避免客户端崩溃
      return proto.Empty();
    }
    _lastWalkAt = now;
    if (!request.x.isFinite || !request.y.isFinite || !request.z.isFinite) {
      _log.warning('Walk ignored: NaN or Inf in direction');
      return proto.Empty();
    }
    final dir = request.toVM();
    final mag = dir.length;
    if (mag > 3.0) {
      _log.warning(
        'Walk direction magnitude=${mag.toStringAsFixed(2)} '
        'exceeds max=3.0 — clamped',
      );
      dir.normalize();
      dir.scale(3.0);
    }
    if (_m.state is Grounded || _m.state is Zero || _m.state is Transitioning) {
      _log.fine('Walk ignored: ${_m.state.runtimeType}');
      return proto.Empty();
    }
    _dispatch(A.walk(dir));
    _lastWalkX = dir.x;
    _lastWalkY = dir.y;
    return proto.Empty();
  }

  @override
  Future<proto.ControlLease> acquireControl(
    ServiceCall call,
    proto.AcquireControlRequest request,
  ) async {
    final callerPrincipal = _requireMotionPrincipal(call);
    final clientId = request.clientId.trim();
    if (clientId.isEmpty) {
      return _rejectedLease(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_LEASE_MISSING,
      );
    }
    if (mode == CmsMode.hardware && clientId != callerPrincipal) {
      throw GrpcError.permissionDenied(
        'AcquireControl client_id must match the authenticated principal',
      );
    }
    if (_grpcLease.active) {
      return _rejectedLease(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_CONTROL_BUSY,
      );
    }
    final precondition = _motionPrecondition();
    if (precondition != proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE) {
      return _rejectedLease(precondition);
    }
    final a = arbiter;
    if (a != null && !a.tryAcquire(ControlSource.grpc)) {
      return _rejectedLease(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_CONTROL_BUSY,
      );
    }
    _leaseOwnerId = clientId;
    _initialZeroAcknowledged = false;
    _lastAcceptedWalk = null;
    _lastWalkAt = null;
    final token = _grpcLease.acquire();
    _lastControlDecision = proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE;
    return proto.ControlLease(
      accepted: true,
      token: token,
      leaseDurationMs: grpcLeaseTimeout.inMilliseconds,
      reason: _lastControlDecision,
      status: _controlStatus(),
    );
  }

  @override
  Future<proto.ControlLease> renewControlLease(
    ServiceCall call,
    proto.ControlLeaseRequest request,
  ) async {
    _requireMotionLeaseOwner(call);
    final token = request.token;
    if (!_grpcLease.isValid(token)) {
      return _rejectedLease(_missingOrExpiredLease(token));
    }
    final precondition = _motionPrecondition(requireGrpcOwner: true);
    if (precondition != proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE) {
      _revokeGrpcControl(precondition);
      return _rejectedLease(precondition);
    }
    final a = arbiter;
    if (a != null &&
        (a.owner != ControlSource.grpc || !a.tryAcquire(ControlSource.grpc))) {
      _grpcLease.invalidate();
      _leaseOwnerId = '';
      return _rejectedLease(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_PREEMPTED,
      );
    }
    _grpcLease.renew(token);
    _lastControlDecision = proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE;
    return proto.ControlLease(
      accepted: true,
      token: token,
      leaseDurationMs: grpcLeaseTimeout.inMilliseconds,
      reason: _lastControlDecision,
      status: _controlStatus(),
    );
  }

  @override
  Future<proto.ControlStatus> releaseControl(
    ServiceCall call,
    proto.ControlLeaseRequest request,
  ) async {
    _requireMotionLeaseOwner(call);
    if (!_grpcLease.isValid(request.token)) {
      _lastControlDecision = _missingOrExpiredLease(request.token);
      return _controlStatus();
    }
    _revokeGrpcControl(proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE);
    return _controlStatus();
  }

  @override
  Future<proto.CommandAck> walkChecked(
    ServiceCall call,
    proto.WalkRequest request,
  ) async {
    _requireMotionLeaseOwner(call);
    final token = request.token;
    if (!_grpcLease.isValid(token)) {
      return _rejectedWalk(request, _missingOrExpiredLease(token));
    }
    if (request.sequence.isZero) {
      return _rejectSequenceViolation(
        request,
        'must be a positive uint64, got zero',
      );
    }
    if (!request.hasDirection() ||
        !request.direction.x.isFinite ||
        !request.direction.y.isFinite ||
        !request.direction.z.isFinite) {
      _revokeGrpcControl(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_INVALID_VECTOR,
      );
      return _rejectedWalk(
        request,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_INVALID_VECTOR,
      );
    }
    final precondition = _motionPrecondition(requireGrpcOwner: true);
    if (precondition != proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE) {
      _revokeGrpcControl(precondition);
      return _rejectedWalk(request, precondition);
    }
    final lastAccepted = _lastAcceptedWalk;
    if (lastAccepted != null && request.sequence == lastAccepted.sequence) {
      if (_sameWalkPayload(request, lastAccepted)) {
        _grpcLease.renew(token);
        _lastControlDecision =
            proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE;
        return proto.CommandAck(
          accepted: true,
          reason: _lastControlDecision,
          sequence: request.sequence,
          status: _controlStatus(),
        );
      }
      return _rejectSequenceViolation(
        request,
        'replay ${request.sequence} changed the payload',
      );
    }
    if (lastAccepted != null && request.sequence != lastAccepted.sequence + 1) {
      return _rejectSequenceViolation(
        request,
        'expected ${lastAccepted.sequence + 1} after '
        '${lastAccepted.sequence}, got ${request.sequence}',
      );
    }
    final now = _monotonicClock.elapsed;
    if (_lastWalkAt != null && now - _lastWalkAt! < _minWalkInterval) {
      _revokeGrpcControl(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED,
      );
      return _rejectedWalk(
        request,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED,
      );
    }

    final dir = request.direction.toVM();
    if (!_velocityWithinLimits(dir)) {
      _revokeGrpcControl(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_INVALID_VECTOR,
      );
      return _rejectedWalk(
        request,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_INVALID_VECTOR,
      );
    }
    if (!_initialZeroAcknowledged && !_isZeroVelocity(dir)) {
      return _rejectedWalk(
        request,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_CONTROL_BUSY,
      );
    }
    _lastWalkAt = now;
    if (!_dispatch(A.walk(dir))) {
      _grpcLease.invalidate();
      _leaseOwnerId = '';
      return _rejectedWalk(
        request,
        proto.CommandRejectReason.COMMAND_REJECT_REASON_PREEMPTED,
      );
    }
    _lastWalkX = dir.x;
    _lastWalkY = dir.y;
    _lastWalkZ = dir.z;
    _grpcLease.renew(token);
    _lastAcceptedWalk = request.deepCopy();
    if (_isZeroVelocity(dir)) {
      _initialZeroAcknowledged = true;
    }
    _grpcMotionIssued = true;
    _acceptedControlCommands++;
    _lastControlDecision = proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE;
    return proto.CommandAck(
      accepted: true,
      reason: _lastControlDecision,
      sequence: request.sequence,
      status: _controlStatus(),
    );
  }

  static bool _sameWalkPayload(
    proto.WalkRequest left,
    proto.WalkRequest right,
  ) {
    final leftBytes = left.writeToBuffer();
    final rightBytes = right.writeToBuffer();
    if (leftBytes.length != rightBytes.length) return false;
    for (var index = 0; index < leftBytes.length; index++) {
      if (leftBytes[index] != rightBytes[index]) return false;
    }
    return true;
  }

  proto.CommandAck _rejectSequenceViolation(
    proto.WalkRequest request,
    String details,
  ) {
    _log.warning('WalkChecked rejected: sequence order violation ($details)');
    const reason = proto.CommandRejectReason.COMMAND_REJECT_REASON_RATE_LIMITED;
    _revokeGrpcControl(reason);
    return _rejectedWalk(request, reason);
  }

  @override
  Future<proto.ControlStatus> getControlStatus(
    ServiceCall call,
    proto.Empty request,
  ) async {
    return _controlStatus();
  }

  proto.ControlLease _rejectedLease(proto.CommandRejectReason reason) {
    _rejectedControlCommands++;
    _lastControlDecision = reason;
    return proto.ControlLease(
      accepted: false,
      leaseDurationMs: grpcLeaseTimeout.inMilliseconds,
      reason: reason,
      status: _controlStatus(),
    );
  }

  proto.CommandAck _rejectedWalk(
    proto.WalkRequest request,
    proto.CommandRejectReason reason,
  ) {
    _rejectedControlCommands++;
    _lastControlDecision = reason;
    return proto.CommandAck(
      accepted: false,
      reason: reason,
      sequence: request.sequence,
      status: _controlStatus(),
    );
  }

  proto.CommandRejectReason _missingOrExpiredLease(String token) =>
      token.isEmpty
      ? proto.CommandRejectReason.COMMAND_REJECT_REASON_LEASE_MISSING
      : proto.CommandRejectReason.COMMAND_REJECT_REASON_LEASE_EXPIRED;

  String? _motionCallerPrincipal(ServiceCall call) {
    if (mode != CmsMode.hardware) return '';
    final remote = call.remoteAddress;
    if (remote == null) return null;
    if (developmentPlaintext) {
      return lanDevelopmentPrincipal(call, hardwareMotionPeerAddresses);
    }
    final certificate = call.clientCertificate;
    if (remote.isLoopback && certificate == null) return _localGrpcPrincipal;
    if (!remote.isLoopback &&
        !hardwareMotionPeerAddresses.contains(remote.address)) {
      return null;
    }
    if (certificate == null) return null;
    for (final entry in hardwareMotionPrincipals.entries) {
      if (_sameCertificate(certificate.der, entry.value)) return entry.key;
    }
    return null;
  }

  String _requireMotionPrincipal(ServiceCall call) {
    final principal = _motionCallerPrincipal(call);
    if (principal == null) {
      throw GrpcError.permissionDenied(
        'Caller is not authorized for locomotion control',
      );
    }
    return principal;
  }

  void _requireMotionLeaseOwner(ServiceCall call) {
    if (mode == CmsMode.hardware &&
        _requireMotionPrincipal(call) != _leaseOwnerId) {
      throw GrpcError.permissionDenied(
        'Caller does not own the active locomotion lease',
      );
    }
  }

  void _requireActuatorCaller(
    ServiceCall call, {
    bool allowRecoveryStop = false,
  }) {
    if (_motionCallerPrincipal(call) == null) {
      throw GrpcError.permissionDenied(
        'Caller is not authorized for hardware actuator control',
      );
    }
    if (!allowRecoveryStop && recovery?.selected == true) {
      throw GrpcError.failedPrecondition(
        'Exit recovery before normal actuator operations',
      );
    }
  }

  proto.CommandRejectReason _motionPrecondition({
    bool requireGrpcOwner = false,
  }) {
    if (profileManager?.hasFault == true) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_FSM_NOT_READY;
    }
    if (!_motorOutputEnabled) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTORS_DISABLED;
    }
    if (_criticalMotorFault) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTOR_FAULT;
    }
    if (mode == CmsMode.hardware &&
        (_m.isHandlingEvent || _m.profileSwitchInProgress)) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_FSM_NOT_READY;
    }
    if (_m.state is! Standing && _m.state is! Walking) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_FSM_NOT_READY;
    }
    final owner = arbiter?.owner;
    if (owner == ControlSource.yunzhuo) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_CONTROL_BUSY;
    }
    if (requireGrpcOwner && owner != null && owner != ControlSource.grpc) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_PREEMPTED;
    }
    if (requireGrpcOwner && arbiter != null && owner != ControlSource.grpc) {
      return proto.CommandRejectReason.COMMAND_REJECT_REASON_PREEMPTED;
    }
    return proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE;
  }

  bool get _motorOutputEnabled =>
      motorOutputEnabledProvider?.call() ?? mode == CmsMode.simulation;

  bool get _criticalMotorFault => criticalMotorFaultProvider?.call() ?? false;

  proto.ControlOwner get _controlOwner => switch (arbiter?.owner) {
    ControlSource.grpc => proto.ControlOwner.CONTROL_OWNER_GRPC,
    ControlSource.yunzhuo => proto.ControlOwner.CONTROL_OWNER_YUNZHUO,
    null when arbiter == null && _grpcLease.active =>
      proto.ControlOwner.CONTROL_OWNER_GRPC,
    _ => proto.ControlOwner.CONTROL_OWNER_NONE,
  };

  proto.ControlStatus _controlStatus() {
    final owner = _controlOwner;
    final leaseActive =
        _grpcLease.active && owner == proto.ControlOwner.CONTROL_OWNER_GRPC;
    final stateReady =
        (_m.state is Standing || _m.state is Walking) &&
        (mode != CmsMode.hardware ||
            (!_m.isHandlingEvent && !_m.profileSwitchInProgress));
    return proto.ControlStatus(
      fsm: _toCmsState(_m.state),
      motorOutputEnabled: _motorOutputEnabled,
      owner: owner,
      criticalMotorFault: _criticalMotorFault,
      grpcLeaseActive: leaseActive,
      leaseRemainingMs: leaseActive ? _grpcLease.remainingMilliseconds : 0,
      lastAcceptedSequence: _lastAcceptedWalk?.sequence,
      lastDecision: _lastControlDecision,
      readyForWalk:
          leaseActive &&
          _initialZeroAcknowledged &&
          stateReady &&
          profileManager?.hasFault != true &&
          _motorOutputEnabled &&
          !_criticalMotorFault,
      ownerId: switch (owner) {
        proto.ControlOwner.CONTROL_OWNER_GRPC when leaseActive => _leaseOwnerId,
        proto.ControlOwner.CONTROL_OWNER_YUNZHUO => _localRcPrincipal,
        _ => '',
      },
      acceptedCount: _acceptedControlCommands,
      rejectedCount: _rejectedControlCommands,
    );
  }

  void _onControlOwnerChanged(ControlSource? owner) {
    if (owner == ControlSource.grpc || !_grpcLease.active) return;
    if (owner == null) {
      _revokeGrpcControl(
        proto.CommandRejectReason.COMMAND_REJECT_REASON_PREEMPTED,
      );
      return;
    }
    _grpcLease.invalidate();
    _leaseOwnerId = '';
    _grpcMotionIssued = false;
    _lastControlDecision =
        proto.CommandRejectReason.COMMAND_REJECT_REASON_PREEMPTED;
  }

  void _revokeGrpcControl(proto.CommandRejectReason reason) {
    final a = arbiter;
    if (_grpcMotionIssued || _m.state is Walking) {
      if (a != null) {
        if (a.owner == ControlSource.grpc) {
          a.command(
            A.walk(Vector3.zero(), forceWheelStop: true),
            ControlSource.grpc,
          );
          _lastWalkX = 0.0;
          _lastWalkY = 0.0;
          _lastWalkZ = 0.0;
        } else if (a.owner == null) {
          _m.add(A.walk(Vector3.zero(), forceWheelStop: true));
          _lastWalkX = 0.0;
          _lastWalkY = 0.0;
          _lastWalkZ = 0.0;
        }
      } else {
        _m.add(A.walk(Vector3.zero(), forceWheelStop: true));
        _lastWalkX = 0.0;
        _lastWalkY = 0.0;
        _lastWalkZ = 0.0;
      }
    }
    _grpcLease.invalidate();
    a?.release(ControlSource.grpc);
    _leaseOwnerId = '';
    _initialZeroAcknowledged = false;
    _lastAcceptedWalk = null;
    _grpcMotionIssued = false;
    _lastControlDecision = reason;
  }

  void _onGrpcLeaseExpired() {
    _revokeGrpcControl(
      proto.CommandRejectReason.COMMAND_REJECT_REASON_LEASE_EXPIRED,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    recovery?.interrupt('Control server disposed');
    _profileContextVersion++;
    arbiter?.markSafetyChange();
    if (_grpcLease.active) {
      _revokeGrpcControl(proto.CommandRejectReason.COMMAND_REJECT_REASON_NONE);
    }
    _grpcLease.dispose();
    final subscription = _ownerSubscription;
    _ownerSubscription = null;
    await subscription?.cancel();
  }

  @override
  Future<proto.Empty> standUp(ServiceCall call, proto.Empty request) async {
    _requireMotionPrincipal(call);
    if (_disposed || call.isCanceled || call.isTimedOut) {
      throw GrpcError.failedPrecondition('StandUp request is no longer active');
    }
    if (profileManager?.hasFault == true) {
      throw GrpcError.failedPrecondition('Profile state is inconsistent');
    }
    if (!_motorOutputEnabled) {
      throw GrpcError.failedPrecondition('Motors are disabled');
    }
    if (_criticalMotorFault) {
      throw GrpcError.failedPrecondition('Critical motor fault');
    }
    if (mode == CmsMode.hardware &&
        (_m.isHandlingEvent ||
            _m.profileSwitchInProgress ||
            _zeroing ||
            motorEnablePending ||
            externalMotorEnablePendingProvider?.call() == true)) {
      throw GrpcError.failedPrecondition('Body control is busy');
    }
    if (_m.state is Transitioning) {
      if (mode == CmsMode.simulation) return proto.Empty();
      throw GrpcError.failedPrecondition('Body posture is transitioning');
    }
    if (_m.state is Standing) {
      return proto.Empty();
    }
    // Walking must run the existing posture transition, not acknowledge a no-op.
    if (_m.state is Walking &&
        (_grpcLease.active ||
            _lastWalkX.abs() > _walkStopEpsilon ||
            _lastWalkY.abs() > _walkStopEpsilon ||
            _lastWalkZ.abs() > _walkStopEpsilon)) {
      throw GrpcError.failedPrecondition(
        'Stop and release locomotion control before StandUp',
      );
    }
    if (!_dispatch(const A.standUp())) {
      throw GrpcError.aborted('StandUp rejected by control arbiter');
    }
    _lastWalkX = 0.0;
    _lastWalkY = 0.0;
    _lastWalkZ = 0.0;
    _log.info('StandUp command received');
    return proto.Empty();
  }

  static bool _velocityWithinLimits(Vector3 velocity) =>
      velocity.x.abs() <= _maxLinearMps &&
      velocity.y.abs() <= _maxLinearMps &&
      velocity.z.abs() <= _maxYawRps;

  static bool _isZeroVelocity(Vector3 velocity) =>
      velocity.x == 0 && velocity.y == 0 && velocity.z == 0;

  @override
  Future<proto.Empty> sitDown(ServiceCall call, proto.Empty request) async {
    _requireMotionPrincipal(call);
    if (profileManager?.hasFault == true) {
      throw GrpcError.failedPrecondition('Profile state is inconsistent');
    }
    if (!_motorOutputEnabled) {
      throw GrpcError.failedPrecondition('Motors are disabled');
    }
    if (_criticalMotorFault) {
      throw GrpcError.failedPrecondition('Critical motor fault');
    }
    if (_m.state is Transitioning) {
      if (mode == CmsMode.simulation) return proto.Empty();
      throw GrpcError.failedPrecondition('Body posture is transitioning');
    }
    if (_lastWalkX.abs() > _walkStopEpsilon ||
        _lastWalkY.abs() > _walkStopEpsilon ||
        _lastWalkZ.abs() > _walkStopEpsilon) {
      throw GrpcError.failedPrecondition(
        'Body velocity must be zero before SitDown',
      );
    }
    if (_m.state is Grounded) {
      return proto.Empty();
    }
    if (!_dispatch(const A.sitDown())) {
      throw GrpcError.aborted('SitDown rejected by control arbiter');
    }
    _lastWalkX = 0.0;
    _lastWalkY = 0.0;
    _lastWalkZ = 0.0;
    _log.info('SitDown command received');
    return proto.Empty();
  }

  // ═══════════════════════════════════════════════════════════
  //  动作 SDK（Gesture）
  // ═══════════════════════════════════════════════════════════

  /// 触发一个命名动作（鞠躬、点头、扭动等）。
  /// 机器人必须处于 Standing 状态。
  /// 暂无对应 proto RPC，通过 Dart SDK 直接调用。
  void gesture(String name) {
    final library = _brain.gestureLibrary;
    if (library == null || !library.contains(name)) {
      throw GrpcError.notFound('Unknown gesture: $name');
    }
    _dispatch(A.gesture(name));
    _log.info('Gesture command received: $name');
  }

  /// 获取可用动作列表。
  List<String> get gestureNames => _brain.gestureLibrary?.names ?? const [];

  // ═══════════════════════════════════════════════════════════
  //  策略切换
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.ProfileInfo> getProfile(
    ServiceCall call,
    proto.Empty request,
  ) async {
    final pm = profileManager;
    if (pm == null) throw GrpcError.unimplemented('Profiles not configured');
    return _profileInfo(pm);
  }

  proto.ProfileInfo _profileInfo(ProfileManager pm) {
    final slots = mode == CmsMode.hardware && pm.operatorSlots != null;
    final recoveryUnavailable = switch (recovery?.available) {
      true => '',
      false when recovery?.selected == true =>
        'Recovery session is already selected',
      _ => recovery == null
          ? 'Recovery model is not configured'
          : 'Recovery is not available in the current state',
    };
    return proto.ProfileInfo(
      current: pm.currentName,
      available: slots ? pm.operatorNames : pm.names,
      descriptions: slots ? pm.operatorDescriptions : pm.descriptions,
      currentDescription: pm.currentDescription,
      modeCapabilities: [
        proto.RobotModeCapability(
          id: 'recovery',
          kind: proto.RobotModeKind.ROBOT_MODE_KIND_RECOVERY_ACTION,
          availability: recovery?.available == true
              ? proto
                    .RobotModeAvailability
                    .ROBOT_MODE_AVAILABILITY_AVAILABLE
              : proto
                    .RobotModeAvailability
                    .ROBOT_MODE_AVAILABILITY_UNAVAILABLE,
          unavailableReason: recovery?.available == true
              ? ''
              : recoveryUnavailable,
        ),
      ],
      activeModeId: recovery?.selected == true ? 'recovery' : '',
    );
  }

  @override
  Future<proto.ProfileInfo> switchProfile(
    ServiceCall call,
    proto.ProfileRequest request,
  ) async {
    _requireActuatorCaller(call);
    final pm = profileManager;
    if (pm == null) throw GrpcError.unimplemented('Profiles not configured');
    final hardware = mode == CmsMode.hardware;
    final slotMode = hardware && pm.operatorSlots != null;
    final wasStanding = _m.state is Standing;
    void validateState({bool ownLock = false}) {
      if (_disposed || _m.isClosed) {
        throw StateError('Control server is closed');
      }
      if (_zeroing) throw StateError('Joint calibration is still in progress');
      if (pm.hasFault || _criticalMotorFault) {
        throw StateError('A safety fault prevents profile switching');
      }
      if (recovery?.selected == true) {
        throw StateError('Exit recovery before switching profiles');
      }
      if (hardware) {
        if ((_m.state is! Grounded && !(slotMode && _m.state is Standing)) ||
            _m.isHandlingEvent ||
            (!ownLock && _m.profileSwitchInProgress)) {
          throw StateError(
            'Profile switch requires idle Grounded or operator-slot Standing',
          );
        }
        if ((!slotMode && _motorOutputEnabled) ||
            motorEnablePending ||
            externalMotorEnablePendingProvider?.call() == true) {
          throw StateError(
            'Motor enable is pending or administrative switch requires disabled motors',
          );
        }
        if (arbiter?.owner == ControlSource.yunzhuo || _grpcLease.active) {
          throw StateError('Release control before switching profiles');
        }
      } else if (_m.state is! Grounded && !wasStanding) {
        throw StateError('Must be in Grounded or Standing state');
      }
    }

    try {
      validateState();
      final state = _m.state;
      final commands = _m.commandVersion;
      final ownerContext = arbiter?.contextVersion;
      final context = _profileContextVersion;
      final externalContext = externalProfileContextProvider?.call();
      bool canCommit() {
        validateState(ownLock: hardware);
        if (call.isCanceled ||
            call.isTimedOut ||
            !identical(_m.state, state) ||
            _m.commandVersion != commands ||
            arbiter?.contextVersion != ownerContext ||
            externalProfileContextProvider?.call() != externalContext ||
            _profileContextVersion != context) {
          throw StateError('Control context changed during profile loading');
        }
        return true;
      }

      if (hardware) _m.profileSwitchInProgress = true;
      try {
        if (slotMode) {
          await pm.switchOperatorProfile(request.name, canCommit: canCommit);
        } else {
          await pm.switchTo(request.name, canCommit: canCommit);
        }
      } finally {
        if (hardware) _m.profileSwitchInProgress = false;
      }
    } on ArgumentError catch (error) {
      throw GrpcError.invalidArgument('${error.message}');
    } on StateError catch (error) {
      throw GrpcError.failedPrecondition(error.message);
    }
    if (wasStanding && !slotMode) _dispatch(const A.standUp());
    _log.info('Profile switched to: ${pm.currentName}');
    return _profileInfo(pm);
  }

  // ═══════════════════════════════════════════════════════════
  //  仿真接口（仅 simulation 模式可用）
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.History> tick(ServiceCall call, proto.Empty request) async {
    if (mode == CmsMode.hardware) {
      throw GrpcError.failedPrecondition(
        'Tick is not available in hardware mode',
      );
    }
    if (!_brain.isModelLoaded) {
      throw GrpcError.failedPrecondition('Model not loaded');
    }
    try {
      final h = await _brain.tick();
      _log.finest('tick: inferenceUs=${_brain.lastInferenceUs}');
      return h.toProto(
        timestamp: _elapsed(),
        kp: gains?.kp,
        kd: gains?.kd,
        observation: _brain.walk.lastObservation?.toList(),
      );
    } on TimeoutException {
      throw GrpcError.deadlineExceeded('Inference timed out');
    } on StateError catch (e) {
      throw GrpcError.internal(e.message);
    } catch (e, st) {
      _log.severe('tick: unexpected inference error', e, st);
      throw GrpcError.internal('Inference error: $e');
    }
  }

  @override
  Future<proto.Empty> step(ServiceCall call, proto.SimState request) async {
    final injector = simInjector;
    if (injector == null) {
      throw GrpcError.failedPrecondition(
        'Step is only available in simulation mode',
      );
    }
    request.injectInto(injector);
    return proto.Empty();
  }

  // ═══════════════════════════════════════════════════════════
  //  元数据
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.Timestamp> getStartTime(
    ServiceCall call,
    proto.Empty request,
  ) async {
    return proto.Timestamp.fromDateTime(_startTime.toUtc());
  }

  @override
  Future<proto.Params> getParams(ServiceCall call, proto.Empty request) async {
    return proto.Params(
      robot: proto.RobotModel(
        type: robotType,
        initialJointPosition: proto.Matrix4(values: _brain.standingPose.values),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  CMS 状态查询
  // ═══════════════════════════════════════════════════════════

  proto.CmsState _toCmsState(S s) => switch (s) {
    Zero() => proto.CmsState(kind: proto.CmsStateKind.CMS_STATE_KIND_ZERO),
    Grounded() => proto.CmsState(
      kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED,
    ),
    Standing() => proto.CmsState(
      kind: proto.CmsStateKind.CMS_STATE_KIND_STANDING,
    ),
    Walking() => proto.CmsState(
      kind: proto.CmsStateKind.CMS_STATE_KIND_WALKING,
    ),
    Transitioning(:final target) => proto.CmsState(
      kind: proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING,
      transition: switch (target) {
        StandUpCommand() =>
          proto.CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP,
        SitDownCommand() =>
          proto.CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN,
        GestureCommand() => proto.CmsTransitionKind.CMS_TRANSITION_KIND_GESTURE,
        _ => proto.CmsTransitionKind.CMS_TRANSITION_KIND_NONE,
      },
      gestureName: target is GestureCommand ? target.name : null,
    ),
  };

  @override
  Future<proto.CmsState> getCmsState(
    ServiceCall call,
    proto.Empty request,
  ) async {
    return _toCmsState(_m.state);
  }

  @override
  Stream<proto.CmsState> listenCmsState(
    ServiceCall call,
    proto.Empty request,
  ) async* {
    yield _toCmsState(_m.state);
    yield* _m.stream.map(_toCmsState);
  }

  // ═══════════════════════════════════════════════════════════
  //  标零
  // ═══════════════════════════════════════════════════════════

  /// 电机清零：把当前位置标记为零点并保存。
  /// 机器人必须处于 Grounded 状态（趴地/放平后再清零）。
  @override
  Future<proto.Empty> setZero(ServiceCall call, proto.Empty request) async {
    _requireActuatorCaller(call);
    if (_m.state is! Grounded) {
      throw GrpcError.failedPrecondition('Must be in Grounded state');
    }
    final j = joint;
    if (j == null) {
      throw GrpcError.unimplemented(
        'SetZero not available (no joint controller)',
      );
    }
    if (_zeroing) {
      throw GrpcError.resourceExhausted('SetZero already in progress');
    }
    _zeroing = true;
    _profileContextVersion++;
    arbiter?.markSafetyChange();
    try {
      final ok = await j.setZero();
      if (!ok) {
        _log.warning('SetZero completed with suspicious results');
      }
      _log.info('SetZero completed');
      return proto.Empty();
    } finally {
      _zeroing = false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  流式监听
  // ═══════════════════════════════════════════════════════════

  @override
  Stream<proto.History> listenHistory(ServiceCall call, proto.Empty request) {
    return _historyBroadcast.map(
      (h) => h.toProto(timestamp: _elapsed(), kp: gains?.kp, kd: gains?.kd),
    );
  }

  @override
  Stream<proto.Imu> listenImu(ServiceCall call, proto.Empty request) {
    // 硬件模式：使用外部注入的硬件数据流
    final factory = imuStreamFactory;
    if (factory != null) return factory();

    // 仿真模式：时钟驱动，读取 ImuService 当前状态
    return _brain.ts.map(
      (_) => imuSnapshot(
        _brain.imu,
        quaternion: simInjector?.quaternion ?? _identityQ,
        timestamp: _elapsed(),
      ),
    );
  }

  @override
  Stream<proto.Joint> listenJoint(ServiceCall call, proto.Empty request) {
    // 硬件模式：使用外部注入的硬件数据流
    final factory = jointStreamFactory;
    if (factory != null) return factory();

    // 仿真模式：时钟驱动，读取 JointService 当前状态
    return _brain.ts.map(
      (_) => jointSnapshot(_brain.joint, timestamp: _elapsed()),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  诊断接口
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.Voltage> getVoltage(
    ServiceCall call,
    proto.Empty request,
  ) async {
    final j = joint;
    if (j == null) {
      throw GrpcError.failedPrecondition(
        'GetVoltage requires hardware mode with RealJoint',
      );
    }
    final voltages = await j.readVoltage();
    return proto.Voltage(values: voltages.map((v) => v.toDouble()));
  }

  @override
  Future<proto.MotorStatusResponse> getMotorStatus(
    ServiceCall call,
    proto.Empty request,
  ) async {
    final j = joint;
    if (j == null) {
      throw GrpcError.failedPrecondition(
        'GetMotorStatus requires hardware mode with RealJoint',
      );
    }
    final motors = <proto.MotorState>[];
    for (int i = 0; i < 16; i++) {
      final online = j.isOnline(i);
      final report = j.getReport(i);
      motors.add(
        proto.MotorState(
          id: i,
          online: online,
          statusCode: report?.status.value ?? 0,
          temperature: report?.temperature ?? 0.0,
          voltage: 0.0, // voltage requires async getter, use GetVoltage RPC
          position: report?.position ?? 0.0,
          velocity: report?.velocity ?? 0.0,
          torque: report?.torque ?? 0.0,
          errors: report?.errors.errors.map((e) => e.index).toList() ?? [],
        ),
      );
    }
    return proto.MotorStatusResponse(motors: motors);
  }

  @override
  Future<proto.Empty> clearMotorFault(
    ServiceCall call,
    proto.ClearFaultRequest request,
  ) async {
    _requireActuatorCaller(call);
    _revokeGrpcControl(
      proto.CommandRejectReason.COMMAND_REJECT_REASON_MOTOR_FAULT,
    );
    final j = joint;
    if (j == null) {
      throw GrpcError.failedPrecondition(
        'ClearMotorFault requires hardware mode with RealJoint',
      );
    }
    if (request.jointIds.isEmpty) {
      // 清除全部
      await j.disable(clearErrors: true);
      onMotorEnableChanged?.call(false);
      _log.info('ClearMotorFault: all 16 joints cleared');
    } else {
      // 清除指定关节
      for (final id in request.jointIds) {
        if (id >= 0 && id < 16) {
          j.clearFaultSingle(id);
        }
      }
      _log.info('ClearMotorFault: joints ${request.jointIds} cleared');
    }
    return proto.Empty();
  }

  // ═══════════════════════════════════════════════════════════
  //  未实现的 RPC — pre-existing gap
  //  cms.proto 里声明了这些 RPC 但 server 一直没实现。
  //  Stub 返回 UNIMPLEMENTED 错误，让 dart analyze 通过且客户端能拿到
  //  明确的"未支持"信号，不是静默的 abstract error。
  //  TODO: 实现实际业务逻辑或从 proto 里移除这些 RPC。
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.Empty> setSpeedMode(
    ServiceCall call,
    proto.SpeedModeRequest request,
  ) async {
    throw GrpcError.unimplemented('SetSpeedMode not yet implemented');
  }

  @override
  Future<proto.SpeedModeRequest> getSpeedMode(
    ServiceCall call,
    proto.Empty request,
  ) async {
    throw GrpcError.unimplemented('GetSpeedMode not yet implemented');
  }

  @override
  Future<proto.Empty> playGesture(
    ServiceCall call,
    proto.GestureRequest request,
  ) async {
    throw GrpcError.unimplemented('PlayGesture not yet implemented');
  }

  @override
  Future<proto.GestureList> listGestures(
    ServiceCall call,
    proto.Empty request,
  ) async {
    throw GrpcError.unimplemented('ListGestures not yet implemented');
  }
}
