import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';

import '../recovery/normal_recovery_runtime.dart';

class RecoveryService extends proto.RobotRecoveryServiceBase {
  final NormalRecoveryRuntime? runtime;
  final String Function(ServiceCall) principal;
  RecoveryService(this.runtime, this.principal);

  NormalRecoveryRuntime get _runtime =>
      runtime ??
      (throw GrpcError.unimplemented('Recovery model is not configured'));

  proto.RecoveryStatus _status(String owner, {bool includeToken = false}) {
    final r = runtime;
    return proto.RecoveryStatus(
      availability: r?.available == true
          ? proto.RobotModeAvailability.ROBOT_MODE_AVAILABILITY_AVAILABLE
          : proto.RobotModeAvailability.ROBOT_MODE_AVAILABILITY_UNAVAILABLE,
      phase: r == null
          ? proto.RecoveryPhase.RECOVERY_PHASE_UNKNOWN
          : proto.RecoveryPhase.valueOf(r.controller.phase.index + 1),
      selected: r?.selected ?? false,
      operationId: r?.operationId ?? '',
      sessionToken: includeToken ? r?.tokenFor(owner) ?? '' : '',
      motorDisableConfirmed: r?.stopConfirmed ?? false,
      unavailableReason: r == null
          ? 'Recovery model is not configured'
          : r.available
          ? ''
          : 'Recovery requires verified setup or an active session',
    );
  }

  Future<T> _checked<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on StateError catch (error) {
      throw GrpcError.failedPrecondition(error.message);
    }
  }

  @override
  Future<proto.RecoveryStatus> getStatus(
    ServiceCall call,
    proto.Empty request,
  ) async => _status(principal(call));

  @override
  Future<proto.RecoveryStatus> enter(
    ServiceCall call,
    proto.RecoveryStartRequest request,
  ) => _checked(() async {
    final owner = principal(call);
    _runtime.enter(owner, request.operationId);
    return _status(owner, includeToken: true);
  });
  @override
  Future<proto.RecoveryStatus> enable(
    ServiceCall call,
    proto.RecoverySessionRequest request,
  ) => _checked(() async {
    final owner = principal(call);
    await _runtime.enable(owner, request.sessionToken);
    return _status(owner);
  });
  @override
  Future<proto.RecoveryStatus> heartbeat(
    ServiceCall call,
    proto.RecoverySessionRequest request,
  ) => _checked(() async {
    final owner = principal(call);
    _runtime.heartbeat(owner, request.sessionToken);
    return _status(owner);
  });
  @override
  Future<proto.RecoveryStatus> exit(
    ServiceCall call,
    proto.RecoverySessionRequest request,
  ) => _checked(() async {
    final owner = principal(call);
    await _runtime.exit(owner, request.sessionToken);
    return _status(owner);
  });
  @override
  Future<proto.RecoveryActionReply> start(
    ServiceCall call,
    proto.RecoveryStartRequest request,
  ) => _checked(() async {
    final accepted = await _runtime.start(
      principal(call),
      request.sessionToken,
      request.operationId,
    );
    return proto.RecoveryActionReply(
      operationId: request.operationId,
      decision: accepted
          ? proto.RecoveryActionDecision.RECOVERY_ACTION_DECISION_ACCEPTED
          : proto.RecoveryActionDecision.RECOVERY_ACTION_DECISION_REJECTED,
      phase: proto.RecoveryPhase.valueOf(_runtime.controller.phase.index + 1),
    );
  });
  @override
  Future<proto.RecoveryActionReply> cancel(
    ServiceCall call,
    proto.RecoveryCancelRequest request,
  ) => _checked(() async {
    final owner = principal(call);
    _runtime.authorize(owner, request.sessionToken, requireLive: false);
    if (request.operationId != _runtime.operationId) {
      throw StateError('Unknown recovery operation');
    }
    await _runtime.cancel(owner, request.sessionToken);
    return proto.RecoveryActionReply(
      operationId: request.operationId,
      decision: proto.RecoveryActionDecision.RECOVERY_ACTION_DECISION_ACCEPTED,
      phase: proto.RecoveryPhase.valueOf(_runtime.controller.phase.index + 1),
      reason: _runtime.stopConfirmed
          ? 'Motor disable confirmed'
          : 'Physical stop unconfirmed',
    );
  });
}
