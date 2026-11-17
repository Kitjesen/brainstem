import 'dart:async';

import 'package:logging/logging.dart';
import 'package:pcan/pcan.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

import 'supported.dart';

export 'package:pcan/pcan.dart';

final _logger = Logger('PcanController');

class PcanController<E, S> {
  final Pcan _pcan;
  final _controller = StreamController<S>.broadcast();
  final PcanBaudRate baudRate;
  final Duration frequency;
  final int maxWriteRetries;
  final Duration writeInterval;
  int _nextWriteUs = 0;
  Timer? _timer;
  Timer? _retryTimer;
  final Stopwatch _clock;
  final _pending =
      <Object, ({E event, PcanMessage message, int attempt, int deadline})>{};
  final _disabledMotors = <int>{};
  bool _closed = false;
  int _lastFailureLogMs = -1000;
  int failedWrites = 0;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 10;

  final _eventConverter = eventConverter[E]! as PcanMessage Function(E);
  final _stateConverter = stateConverter[S]! as S Function(PcanMessage);

  PcanController(
    PcanChannel channel, {
    this.baudRate = .baud1M,
    this.frequency = const .new(milliseconds: 1),
    this.maxWriteRetries = 3,
    this.writeInterval = Duration.zero,
  }) : _pcan = Pcan(channel),
       _clock = Stopwatch()..start();

  PcanController.withPcan(
    this._pcan, {
    this.baudRate = PcanBaudRate.baud1M,
    this.frequency = const Duration(milliseconds: 1),
    this.maxWriteRetries = 3,
    this.writeInterval = Duration.zero,
    Stopwatch? clock,
  }) : _clock = clock ?? (Stopwatch()..start());

  int get pendingWrites => _pending.length;

  bool get canWriteImmediately =>
      !_closed && writeInterval == Duration.zero && _pending.isEmpty;

  /// Calibration must not be deferred past its stationary admission check.
  bool tryWriteImmediately(E event) {
    if (!canWriteImmediately) return false;
    final result = _write(_eventConverter(event));
    if (result == PcanStatus.ok) return true;
    _recordFailure(event, result);
    return false;
  }

  bool open() {
    if (_timer != null) {
      _logger.warning('PCAN is already opened.');
      return false;
    }
    final result = _pcan.open(baudRate);
    if (result != .ok) {
      _logger.severe('open ${_pcan.transportName} failed: $result');
      return false;
    }
    _logger.info('${_pcan.transportName} opened successfully.');
    _closed = false;
    _consecutiveErrors = 0;
    _nextWriteUs = 0;
    _timer = Timer.periodic(frequency, (timer) {
      final (message, timestamp, status) = _pcan.read();
      if (status == .qrcvempty) {
        _consecutiveErrors = 0;
        return;
      }
      if (status == .qxmtfull) {
        _pcan.reset();
        _consecutiveErrors++;
        _logger.warning(
          'PCAN buffer full, resetting... '
          '(consecutive errors: $_consecutiveErrors)',
        );
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          _logger.severe(
            'PCAN ${_pcan.transportName}: too many consecutive errors, '
            'attempting full reopen...',
          );
          _reopen();
        }
        return;
      }
      if (status != .ok) {
        _consecutiveErrors++;
        _logger.severe('PCAN error: $status');
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          _logger.severe(
            'PCAN ${_pcan.transportName}: too many consecutive errors, '
            'attempting full reopen...',
          );
          _reopen();
        }
        return;
      }
      _consecutiveErrors = 0;
      try {
        _controller.add(_stateConverter(message));
      } on UnimplementedError catch (e) {
        _logger.fine('Skipping unsupported frame: $e');
      } on ArgumentError catch (e) {
        _logger.fine('Skipping malformed frame: $e');
      }
    });
    return true;
  }

  void _reopen() {
    clearPendingWrites();
    _timer?.cancel();
    _timer = null;
    _pcan.close();
    _consecutiveErrors = 0;
    _logger.info('PCAN ${_pcan.transportName}: reopening...');
    if (!open()) {
      _logger.severe('PCAN ${_pcan.transportName}: reopen failed');
    }
  }

  void add(E event) {
    if (_closed) return;
    // A stop supersedes stale motion and queued enables for that motor.
    if (event case RSEventDisable(:final canId)) {
      _disabledMotors.add(canId);
      _pending.removeWhere(
        (_, p) => switch (p.event) {
          RSEventControl(canId: final id) ||
          RSEventEnable(canId: final id) => id == canId,
          _ => false,
        },
      );
    } else if (event case RSEventEnable(:final canId)) {
      _disabledMotors.remove(canId);
    } else if (event case RSEventControl(:final canId)) {
      if (_disabledMotors.contains(canId)) return;
    }
    final msg = _eventConverter(event);
    // Only motion is replaceable. Distinct parameter writes are not coalesced.
    final Object key = event is RSEventControl
        ? ('control', event.canId)
        : Object();
    _pending.remove(key);
    if (writeInterval > Duration.zero &&
        (_pending.isNotEmpty || _clock.elapsedMicroseconds < _nextWriteUs)) {
      _enqueue(key, event, msg, 0);
      return;
    }
    final result = _write(msg);
    if (result == .ok) return;
    _recordFailure(event, result);
    if (!_retryable(result) || maxWriteRetries <= 1) return;
    _enqueue(key, event, msg, 1);
  }

  PcanStatus _write(PcanMessage message) {
    final result = _pcan.write(message);
    _nextWriteUs = _clock.elapsedMicroseconds + writeInterval.inMicroseconds;
    return result;
  }

  void _enqueue(Object key, E event, PcanMessage message, int attempt) {
    if (_pending.length >= 64) {
      _logger.severe(
        'PCAN ${_pcan.transportName}: retry capacity reached; dropping $event',
      );
      return;
    }
    _pending[key] = (
      event: event,
      message: message,
      attempt: attempt,
      deadline:
          _clock.elapsedMilliseconds + (event is RSEventControl ? 20 : 100),
    );
    _scheduleRetry();
  }

  bool _retryable(PcanStatus s) => s == .xmtfull || s == .qxmtfull;

  void _recordFailure(E event, PcanStatus result) {
    failedWrites++;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastFailureLogMs >= 1000) {
      _lastFailureLogMs = now;
      _logger.severe(
        'PCAN ${_pcan.transportName}: send $event failed: $result '
        'errno=${_pcan.lastWriteErrno}, totalFailures=$failedWrites',
      );
    }
  }

  void _scheduleRetry() {
    final remaining = _nextWriteUs - _clock.elapsedMicroseconds;
    final delay = writeInterval > Duration.zero
        ? Duration(microseconds: remaining > 0 ? remaining : 0)
        : const Duration(milliseconds: 2);
    _retryTimer ??= Timer(delay, () {
      _retryTimer = null;
      final entries = _pending.entries.toList();
      entries.sort(
        (a, b) => (a.value.event is RSEventDisable ? 0 : 1).compareTo(
          b.value.event is RSEventDisable ? 0 : 1,
        ),
      );
      for (final entry in entries) {
        final p = entry.value;
        if (_closed || _clock.elapsedMilliseconds >= p.deadline) {
          _pending.remove(entry.key);
          if (!_closed) {
            failedWrites++;
            _logger.severe('${_pcan.transportName}: expired send ${p.event}');
          }
          continue;
        }
        if (writeInterval > Duration.zero &&
            _clock.elapsedMicroseconds < _nextWriteUs) {
          break;
        }
        final result = _write(p.message);
        if (result == .ok) {
          _pending.remove(entry.key);
        } else {
          _recordFailure(p.event, result);
          if (!_retryable(result) || p.attempt + 1 >= maxWriteRetries) {
            _pending.remove(entry.key);
          } else {
            _pending[entry.key] = (
              event: p.event,
              message: p.message,
              attempt: p.attempt + 1,
              deadline: p.deadline,
            );
          }
        }
        if (writeInterval > Duration.zero) break;
      }
      if (_pending.isNotEmpty && !_closed) _scheduleRetry();
    });
  }

  void clearPendingWrites() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pending.clear();
  }

  Stream<S> get state => _controller.stream;

  void close() {
    _closed = true;
    clearPendingWrites();
    _timer?.cancel();
    _timer = null;
    _pcan.close();
    _logger.info('Closing ${_pcan.transportName}.');
  }

  void dispose() {
    close();
    _controller.close();
    _logger.info('Disposing ${_pcan.transportName}.');
  }
}
