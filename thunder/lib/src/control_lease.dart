import 'dart:async';
import 'dart:math';

typedef LeaseTokenFactory = String Function();
typedef LeaseNowFactory = Duration Function();

/// Short-lived ownership proof for the gRPC motion client.
///
/// The lease is deliberately independent from the longer operator arbitration
/// timeout. A lost gRPC client must request a safe stop within hundreds of
/// milliseconds while the physical controller remains usable.
class GrpcControlLease {
  final Duration timeout;
  final LeaseTokenFactory _tokenFactory;
  final LeaseNowFactory _nowFactory;
  final void Function() _onExpired;

  Timer? _timer;
  String? _token;
  Duration? _expiresAt;
  bool _disposed = false;

  GrpcControlLease({
    this.timeout = const Duration(milliseconds: 300),
    LeaseTokenFactory? tokenFactory,
    LeaseNowFactory? nowFactory,
    required void Function() onExpired,
  }) : _tokenFactory = tokenFactory ?? _secureToken,
       _nowFactory = nowFactory ?? _monotonicNow,
       _onExpired = onExpired;

  String acquire() {
    _ensureActive();
    final token = _tokenFactory();
    if (token.isEmpty) {
      throw StateError('lease token must not be empty');
    }
    _token = token;
    _arm();
    return token;
  }

  bool isValid(String token) {
    if (_disposed || _token == null) return false;
    if (_deadlineReached()) {
      _expire();
      return false;
    }
    return token.isNotEmpty && token == _token;
  }

  bool renew(String token) {
    if (!isValid(token)) return false;
    _arm();
    return true;
  }

  bool release(String token) {
    if (!isValid(token)) return false;
    invalidate();
    return true;
  }

  bool get active {
    if (_disposed || _token == null) return false;
    if (_deadlineReached()) {
      _expire();
      return false;
    }
    return true;
  }

  String? get token => _token;

  int get remainingMilliseconds {
    final expiresAt = _expiresAt;
    if (!active || expiresAt == null) return 0;
    return max(0, (expiresAt - _nowFactory()).inMilliseconds);
  }

  void invalidate() {
    _timer?.cancel();
    _timer = null;
    _token = null;
    _expiresAt = null;
  }

  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
  }

  void _arm() {
    _timer?.cancel();
    _expiresAt = _nowFactory() + timeout;
    _timer = Timer(timeout, _expire);
  }

  bool _deadlineReached() {
    final expiresAt = _expiresAt;
    return expiresAt == null || _nowFactory() >= expiresAt;
  }

  void _expire() {
    if (_disposed || _token == null) return;
    _timer?.cancel();
    _timer = null;
    _token = null;
    _expiresAt = null;
    _onExpired();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('lease is disposed');
  }

  static String _secureToken() {
    final random = Random.secure();
    final values = List<int>.generate(4, (_) => random.nextInt(1 << 32));
    return values
        .map((value) => value.toRadixString(16).padLeft(8, '0'))
        .join();
  }

  static final Stopwatch _monotonicClock = Stopwatch()..start();

  static Duration _monotonicNow() => _monotonicClock.elapsed;
}
