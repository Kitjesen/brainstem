import 'dart:async';

import 'package:logging/logging.dart';
import 'package:pcan/pcan.dart';

import 'supported.dart';

export 'package:pcan/pcan.dart';

final _logger = Logger('PcanController');

class PcanController<E, S> {
  final Pcan _pcan;
  final _controller = StreamController<S>.broadcast();
  final PcanBaudRate baudRate;
  final Duration frequency;
  final int maxWriteRetries;
  Timer? _timer;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 10;

  final _eventConverter = eventConverter[E]! as PcanMessage Function(E);
  final _stateConverter = stateConverter[S]! as S Function(PcanMessage);

  PcanController(
    PcanChannel channel, {
    this.baudRate = .baud1M,
    this.frequency = const .new(milliseconds: 1),
    this.maxWriteRetries = 3,
  }) : _pcan = Pcan(channel);

  bool open() {
    if (_timer != null) {
      _logger.warning('PCAN is already opened.');
      return false;
    }
    final result = _pcan.open(baudRate);
    if (result != .ok) {
      _logger.severe('open ${_pcan.channel} failed: $result');
      return false;
    }
    _logger.info('${_pcan.channel} opened successfully.');
    _consecutiveErrors = 0;
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
            'PCAN ${_pcan.channel}: too many consecutive errors, '
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
            'PCAN ${_pcan.channel}: too many consecutive errors, '
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
    _timer?.cancel();
    _timer = null;
    _pcan.close();
    _consecutiveErrors = 0;
    _logger.info('PCAN ${_pcan.channel}: reopening...');
    if (!open()) {
      _logger.severe('PCAN ${_pcan.channel}: reopen failed');
    }
  }

  void add(E event) {
    final msg = _eventConverter(event);
    for (int attempt = 0; attempt < maxWriteRetries; attempt++) {
      final result = _pcan.write(msg);
      if (result == .ok) return;
      if (result == .qxmtfull) {
        _pcan.reset();
        _logger.warning(
          'PCAN write buffer full on attempt ${attempt + 1}, '
          'reset and retrying...',
        );
        continue;
      }
      _logger.severe('send $event: $result (attempt ${attempt + 1})');
      return;
    }
    _logger.severe('send $event: failed after $maxWriteRetries retries');
  }

  Stream<S> get state => _controller.stream;

  void close() {
    _timer?.cancel();
    _pcan.close();
    _logger.info('Closing ${_pcan.channel}.');
  }

  void dispose() {
    close();
    _controller.close();
    _logger.info('Disposing ${_pcan.channel}.');
  }
}
