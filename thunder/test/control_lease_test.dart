import 'package:fake_async/fake_async.dart';
import 'package:thunder/src/control_lease.dart';
import 'package:test/test.dart';

void main() {
  test('expired gRPC lease is invalidated and requests one safe stop', () {
    fakeAsync((async) {
      var stopRequests = 0;
      final lease = GrpcControlLease(
        timeout: const Duration(milliseconds: 300),
        tokenFactory: () => 'lingtu-token',
        onExpired: () => stopRequests++,
      );

      final token = lease.acquire();
      expect(lease.isValid(token), isTrue);

      async.elapse(const Duration(milliseconds: 299));
      expect(lease.isValid(token), isTrue);
      expect(stopRequests, 0);

      async.elapse(const Duration(milliseconds: 1));
      expect(lease.isValid(token), isFalse);
      expect(stopRequests, 1);

      async.elapse(const Duration(seconds: 1));
      expect(stopRequests, 1);
    });
  });

  test(
    'deadline check expires a lease even before its timer callback runs',
    () {
      var now = Duration.zero;
      var stopRequests = 0;
      final lease = GrpcControlLease(
        timeout: const Duration(milliseconds: 300),
        tokenFactory: () => 'lingtu-token',
        nowFactory: () => now,
        onExpired: () => stopRequests++,
      );

      final token = lease.acquire();
      now += const Duration(milliseconds: 301);

      expect(lease.isValid(token), isFalse);
      expect(lease.active, isFalse);
      expect(stopRequests, 1);
      lease.dispose();
      expect(stopRequests, 1);
    },
  );
}
