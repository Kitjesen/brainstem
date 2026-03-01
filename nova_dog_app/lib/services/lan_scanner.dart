import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart' hide Duration;

class LanScanResult {
  final String ip;
  final int port;
  final String hostname; // from reverse DNS, or same as ip
  final bool isRobot; // confirmed via gRPC handshake

  const LanScanResult({
    required this.ip,
    required this.port,
    required this.hostname,
    required this.isRobot,
  });

  /// Display label: hostname if it differs from ip, otherwise ip.
  String get label => (hostname != ip && hostname.isNotEmpty) ? hostname : ip;
}

/// Scans the local network for open ports and optionally verifies han_dog robots.
class LanScanner {
  static const int _concurrency = 50;

  /// Returns unique IPv4 subnet prefixes of all local interfaces
  /// (e.g. ["192.168.66.", "10.0.0."]).
  static Future<List<String>> localSubnets() async {
    final subnets = <String>{};
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4 && parts[0] != '127') {
            subnets.add('${parts[0]}.${parts[1]}.${parts[2]}.');
          }
        }
      }
    } catch (_) {}
    return subnets.toList();
  }

  /// Scans [subnet]1–254 on [port].
  ///
  /// Yields a [LanScanResult] for each host that accepts a TCP connection.
  /// [onProgress] is called after each probe with (scanned, total).
  static Stream<LanScanResult> scan(
    String subnet,
    int port, {
    void Function(int scanned, int total)? onProgress,
  }) {
    final controller = StreamController<LanScanResult>();
    _runScan(subnet, port, controller, onProgress);
    return controller.stream;
  }

  static Future<void> _runScan(
    String subnet,
    int port,
    StreamController<LanScanResult> controller,
    void Function(int, int)? onProgress,
  ) async {
    final sem = _Semaphore(_concurrency);
    int scanned = 0;

    await Future.wait(List.generate(254, (i) => sem.run(() async {
          final ip = '$subnet${i + 1}';
          Socket? sock;
          try {
            sock = await Socket.connect(ip, port,
                timeout: const Duration(milliseconds: 500));
            sock.destroy();
            sock = null;

            // Reverse DNS for hostname
            String hostname = ip;
            try {
              final rev = await InternetAddress(ip).reverse();
              if (rev.host.isNotEmpty && rev.host != ip) hostname = rev.host;
            } catch (_) {}

            // gRPC probe — confirms it's a han_dog robot
            final isRobot = await _checkGrpc(ip, port);

            if (!controller.isClosed) {
              controller.add(LanScanResult(
                  ip: ip, port: port, hostname: hostname, isRobot: isRobot));
            }
          } catch (_) {
            sock?.destroy();
          } finally {
            scanned++;
            onProgress?.call(scanned, 254);
          }
        })));

    if (!controller.isClosed) controller.close();
  }

  /// Calls getStartTime with a 1-second timeout to verify the endpoint
  /// runs the han_dog Cms service.
  static Future<bool> _checkGrpc(String ip, int port) async {
    ClientChannel? ch;
    try {
      ch = ClientChannel(ip,
          port: port,
          options: const ChannelOptions(
              credentials: ChannelCredentials.insecure()));
      final stub = CmsClient(ch);
      await stub.getStartTime(Empty(),
          options: CallOptions(timeout: const Duration(seconds: 1)));
      return true;
    } catch (_) {
      return false;
    } finally {
      await ch?.shutdown();
    }
  }
}

// ── Simple semaphore for concurrency limiting ──
class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _count = 0;
  final _queue = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() fn) async {
    while (_count >= _max) {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    _count++;
    try {
      return await fn();
    } finally {
      _count--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }
}
