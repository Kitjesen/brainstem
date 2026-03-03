import 'dart:async';

/// Debouncer utility to delay execution until a pause in events.
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  /// Runs the action after the specified delay, canceling any pending action.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  /// Cancels any pending action.
  void cancel() {
    _timer?.cancel();
  }

  /// Disposes the debouncer.
  void dispose() {
    _timer?.cancel();
  }
}

/// Throttler utility to limit execution frequency.
class Throttler {
  final int milliseconds;
  Timer? _timer;
  bool _isReady = true;

  Throttler({required this.milliseconds});

  /// Runs the action immediately if ready, then blocks for the specified duration.
  void run(void Function() action) {
    if (_isReady) {
      _isReady = false;
      action();
      _timer = Timer(Duration(milliseconds: milliseconds), () {
        _isReady = true;
      });
    }
  }

  /// Disposes the throttler.
  void dispose() {
    _timer?.cancel();
  }
}
