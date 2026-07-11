import 'dart:async';

import 'package:han_dog_brain/han_dog_brain.dart';

import 'control_arbiter.dart';

/// Owns the logical action-output gate and the physical motor enable state.
///
/// Every hardware path that changes motor torque must use this module. The
/// gate is closed before a disable request is sent so stale control actions
/// cannot be emitted while the physical disable frame is in flight.
class MotorOutputController {
  final MotorService _motor;
  final ControlArbiter? _arbiter;
  final String? Function()? _enableBlockReason;
  final Future<void> Function()? _prepareForEnable;
  final void Function(bool enabled)? _onOutputChanged;

  bool _isEnabled = false;
  bool _physicalDisableConfirmed = true;
  String? _enableInhibitReason;
  Future<void> _operationTail = Future<void>.value();
  int _nextRequestId = 0;

  MotorOutputController({
    required MotorService motor,
    ControlArbiter? arbiter,
    String? Function()? enableBlockReason,
    Future<void> Function()? prepareForEnable,
    void Function(bool enabled)? onOutputChanged,
  }) : _motor = motor,
       _arbiter = arbiter,
       _enableBlockReason = enableBlockReason,
       _prepareForEnable = prepareForEnable,
       _onOutputChanged = onOutputChanged;

  /// Whether control actions may currently reach the motors.
  bool get isEnabled => _isEnabled;

  /// Permanently rejects future enable requests for this process lifetime.
  ///
  /// Use this for latched conditions such as undervoltage. Clearing a safety
  /// latch requires an explicit operator/restart policy outside this class.
  void inhibitEnables(String reason) {
    _enableInhibitReason ??= reason;
  }

  /// Returns a rejection reason when [source] may not enable motor torque.
  String? enableRejection(ControlSource source) {
    final inhibitReason = _enableInhibitReason;
    if (inhibitReason != null) return inhibitReason;
    if (!_physicalDisableConfirmed) {
      return 'motor output is not confirmed disabled';
    }
    if (!(_arbiter?.canActuate(source) ?? true)) {
      final owner = _arbiter?.owner;
      return 'motor enable rejected: ${owner?.name ?? 'another source'} '
          'owns control';
    }
    return _enableBlockReason?.call();
  }

  /// Enables motors when the source has authority and the safety check passes.
  ///
  /// A non-null return value is an expected safety rejection. Hardware errors
  /// are propagated after closing the output gate.
  Future<String?> enable(ControlSource source) {
    final initialRejection = enableRejection(source);
    if (initialRejection != null) {
      return Future<String?>.value(initialRejection);
    }

    final requestId = ++_nextRequestId;
    return _enqueue(() async {
      if (requestId != _nextRequestId) {
        return 'motor enable superseded by a later request';
      }
      final rejection = enableRejection(source);
      if (rejection != null) return rejection;

      try {
        final prepare = _prepareForEnable;
        if (prepare != null) {
          await prepare();
        }
        if (requestId != _nextRequestId) {
          return 'motor enable superseded by a later request';
        }
        final postPrepareRejection = enableRejection(source);
        if (postPrepareRejection != null) {
          return postPrepareRejection;
        }
        await _motor.enable();
        _physicalDisableConfirmed = false;
        if (requestId != _nextRequestId) {
          _setEnabled(false);
          await _bestEffortPhysicalDisable();
          return 'motor enable superseded by a later request';
        }
        _setEnabled(true);
        return null;
      } catch (_) {
        // Enable can succeed on only part of the CAN chain. Do not leave an
        // indeterminate subset of motors torque-enabled after any error.
        _setEnabled(false);
        _physicalDisableConfirmed = false;
        await _bestEffortPhysicalDisable();
        rethrow;
      }
    });
  }

  /// Closes the software gate and then sends the physical disable request.
  Future<void> disable({bool clearErrors = false}) {
    final requestId = ++_nextRequestId;
    _setEnabled(false);
    _physicalDisableConfirmed = false;
    return _enqueue(() async {
      try {
        await _confirmPhysicalDisable(clearErrors: clearErrors);
      } finally {
        if (requestId == _nextRequestId) {
          _setEnabled(false);
        }
      }
    });
  }

  /// Runs maintenance only after all earlier motor operations have completed
  /// and the output gate is still closed.
  ///
  /// This is used for operations such as setting encoder zero: a false gate
  /// alone is not sufficient because a physical Disable CAN frame may still
  /// be queued, in flight, or may have failed. A fresh Disable must succeed
  /// in this queue position before the maintenance operation can run.
  Future<T> runWhileDisabled<T>(Future<T> Function() operation) {
    if (_isEnabled) {
      return Future<T>.error(
        StateError('Motors must be disabled before maintenance'),
      );
    }
    return _enqueue(() async {
      if (_isEnabled) {
        throw StateError('Motors must be disabled before maintenance');
      }
      await _confirmPhysicalDisable();
      return operation();
    });
  }

  /// Closes the output gate, confirms a physical disable, then runs
  /// [operation] serially. Use this for fault recovery that must make a
  /// currently-enabled robot safe before doing per-joint maintenance.
  Future<T> disableThenRun<T>(Future<T> Function() operation) {
    final requestId = ++_nextRequestId;
    _setEnabled(false);
    _physicalDisableConfirmed = false;
    return _enqueue(() async {
      try {
        await _confirmPhysicalDisable();
        return operation();
      } finally {
        if (requestId == _nextRequestId) {
          _setEnabled(false);
        }
      }
    });
  }

  Future<void> _confirmPhysicalDisable({bool clearErrors = false}) async {
    _physicalDisableConfirmed = false;
    try {
      await _motor.disable(clearErrors: clearErrors);
      _physicalDisableConfirmed = true;
    } catch (_) {
      _physicalDisableConfirmed = false;
      rethrow;
    }
  }

  Future<void> _bestEffortPhysicalDisable() async {
    try {
      await _confirmPhysicalDisable();
    } catch (_) {
      // Preserve the primary enable failure. The logical output gate remains
      // closed and future Enable requests are rejected until a Disable can be
      // confirmed.
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final future = _operationTail.then<T>((_) => operation());
    _operationTail = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return future;
  }

  void _setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    try {
      _onOutputChanged?.call(enabled);
    } catch (_) {
      // A UI/controller observer must never block a physical safety action.
    }
  }
}
