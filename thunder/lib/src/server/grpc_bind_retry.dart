import 'dart:io';

/// Linux EADDRNOTAVAIL can occur before DHCP assigns the configured LAN address.
/// Other bind errors remain fatal; never fall back to a broader bind address.
Future<T?> bindWhenAddressAvailable<T extends Object>({
  required Future<T> Function() bind,
  required bool Function() shouldStop,
  Duration retryDelay = const Duration(seconds: 2),
  Future<void> Function(Duration)? sleep,
  void Function(SocketException error, int attempt)? onRetry,
}) async {
  if (retryDelay <= Duration.zero) {
    throw ArgumentError.value(retryDelay, 'retryDelay', 'must be positive');
  }
  final delay = sleep ?? Future<void>.delayed;
  var attempt = 0;
  while (!shouldStop()) {
    try {
      return await bind();
    } on SocketException catch (error) {
      if (shouldStop()) return null;
      if (error.osError?.errorCode != 99) rethrow;
      onRetry?.call(error, ++attempt);
      await delay(retryDelay);
    }
  }
  return null;
}
