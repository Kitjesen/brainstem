import 'dart:async';
import 'dart:math';

import 'recovery.dart';

/// One selected recovery session owns the same output path as normal locomotion.
/// A session stays selected after failure until a confirmed disable and explicit exit.
class NormalRecoveryRuntime implements RecoveryOutput {
  final RecoveryInference inference;
  final RecoverySample Function() sample;
  final bool Function() canEnter;
  final bool Function() healthy;
  final bool Function() enabled;
  final Future<void> Function(RecoveryFrame hold) enableHardware;
  final Future<bool> Function() disableHardware;
  final void Function(RecoveryFrame frame) sendHardware;
  final void Function() restoreNormalGains;
  final int Function() nowUs;
  final bool verified;
  late final RecoveryController controller;
  String? _owner, _token, _entryId, _operationId;
  int _expires = 0, _epoch = 0;
  bool _selected = false, _expired = false, _enabling = false;
  bool stopConfirmed = false;
  RecoveryFrame? _hold;
  Future<void>? _stop;
  Future<bool>? _start;

  NormalRecoveryRuntime({
    required this.inference,
    required this.sample,
    required this.canEnter,
    required this.healthy,
    required this.enabled,
    required this.enableHardware,
    required this.disableHardware,
    required this.sendHardware,
    required this.restoreNormalGains,
    required this.nowUs,
    required this.verified,
    required List<double> lower,
    required List<double> upper,
  }) {
    controller = RecoveryController(
      inference: inference,
      output: this,
      guard: RecoveryGainGuard()..active = true,
      nowUs: nowUs,
      lower: lower,
      upper: upper,
    );
  }

  bool get selected => _selected;
  String get operationId => _operationId ?? '';
  String tokenFor(String owner) => owner == _owner ? _token ?? '' : '';
  bool get available { try { return verified && !_selected && canEnter(); } catch (_) { return false; } }
  bool get live { try { return _selected && !_expired && nowUs() < _expires && healthy(); } catch (_) { return false; } }

  String enter(String owner, String id) {
    if (owner.isEmpty || !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) {
      throw StateError('Invalid recovery operation');
    }
    if (_selected) {
      if (owner == _owner && id == _entryId && live) return _token!;
      throw StateError('Recovery session already selected');
    }
    if (!available || enabled()) {
      throw StateError(
        'Recovery requires verified setup, Grounded and disabled motors',
      );
    }
    _owner = owner;
    _entryId = id;
    _operationId = null;
    _start = null;
    _stop = null;
    _expired = false;
    _selected = true;
    stopConfirmed = false;
    ++_epoch;
    final random = Random.secure();
    _token = List<int>.generate(
      24,
      (_) => random.nextInt(256),
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    _expires = nowUs() + 300000;
    return _token!;
  }

  void authorize(String owner, String token, {bool requireLive = true}) {
    if (!_selected || owner != _owner || token.isEmpty || token != _token) {
      throw StateError('Recovery session mismatch');
    }
    if (requireLive && !live) {
      interrupt('Recovery authority expired');
      throw StateError('Recovery authority expired');
    }
  }

  void heartbeat(String owner, String token) {
    authorize(owner, token);
    _expires = nowUs() + 300000;
  }

  Future<void> enable(String owner, String token) async {
    authorize(owner, token);
    if (_enabling || enabled() || _operationId != null || _expired) {
      throw StateError('Recovery cannot enable in this state');
    }
    _enabling = true;
    final epoch = _epoch;
    try {
      await controller.prepareEnable(sample);
      authorize(owner, token);
      if (epoch != _epoch || _hold == null) {
        throw StateError('Recovery enable cancelled');
      }
      await enableHardware(_hold!);
      authorize(owner, token);
      if (epoch != _epoch || !enabled()) {
        throw StateError('Recovery enable unconfirmed');
      }
      controller.enabledConfirmed();
    } catch (_) {
      // A hardware enable may have completed after the first cancellation disable.
      await _stop;
      _stop = null;
      interrupt('Recovery enable failed');
      await _stop;
      rethrow;
    } finally {
      _enabling = false;
    }
  }

  Future<bool> start(String owner, String token, String id) {
    authorize(owner, token);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) {
      throw StateError('Invalid operation ID');
    }
    if (_operationId == id && _start != null) return _start!;
    if (_operationId != null ||
        !enabled() ||
        controller.phase != RecoveryPhase.waiting) {
      throw StateError('Recovery is not ready');
    }
    _operationId = id;
    final epoch = _epoch;
    return _start = () async {
      final accepted = await controller.trigger(sample());
      if (!live || epoch != _epoch) {
        interrupt('Recovery start superseded');
        return false;
      }
      return accepted;
    }();
  }

  Future<void> cancel(String owner, String token) async {
    authorize(owner, token, requireLive: false);
    interrupt('Recovery cancelled');
    await _stop;
  }

  Future<void> exit(String owner, String token) async {
    await cancel(owner, token);
    authorize(owner, token, requireLive: false);
    if (!stopConfirmed || _enabling) {
      throw StateError('Recovery stop is not confirmed');
    }
    restoreNormalGains();
    _selected = false;
    _owner = _token = _entryId = null;
  }

  void interrupt(String reason) {
    if (!_selected) return;
    _expired = true;
    ++_epoch;
    if (controller.phase != RecoveryPhase.failed) {
      controller.abort(reason);
    } else {
      disable(reason);
    }
  }

  Future<void> tick() async {
    if (!_selected) return;
    if (!live) {
      interrupt('Recovery authority lost');
      return;
    }
    try {
      if (enabled()) await controller.tick(sample());
    } catch (_) {
      interrupt('Recovery feedback unavailable');
    }
  }

  Future<void> shutdown() async {
    interrupt('Recovery runtime closed');
    await _stop;
  }

  @override
  void stage(RecoveryFrame frame) {
    if (!live) throw StateError('Recovery authority lost');
    controller.guard.check(frame);
    _hold = frame;
  }

  @override
  void send(RecoveryFrame frame) {
    if (!live || !enabled()) throw StateError('Recovery output unavailable');
    sample().validate();
    controller.guard.check(frame);
    sendHardware(frame);
  }

  @override
  void disable(String reason) {
    _expired = true;
    ++_epoch;
    // Retain the stop result; do not flood CAN on every timer tick after expiry.
    _stop ??= () async {
      stopConfirmed = false;
      try {
        stopConfirmed = await disableHardware();
      } catch (_) {
        stopConfirmed = false;
      }
    }();
  }

  @override
  void standUp() => throw StateError('Explicit normal-mode handover required');
  @override
  void sitDown() => throw StateError('Explicit normal-mode handover required');
}
