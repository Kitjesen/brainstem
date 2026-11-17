import 'dart:async';
import 'dart:io';

import 'package:thunder/src/app/boot_self_check.dart';
import 'package:thunder/src/server/grpc_bind_retry.dart';
import 'package:test/test.dart';

import 'boot_self_check_test.dart' show RecordingVoiceAnnouncer;

SocketException unavailable() => const SocketException(
  'Cannot assign requested address',
  osError: OSError('Cannot assign requested address', 99),
);

void main() {
  test('returns a successful bind without sleeping', () async {
    var slept = false;
    expect(
      await bindWhenAddressAvailable(
        bind: () async => 'listener',
        shouldStop: () => false,
        sleep: (_) async {
          slept = true;
        },
      ),
      'listener',
    );
    expect(slept, isFalse);
  });

  test(
    'retries only address-not-available until the same bind succeeds',
    () async {
      var calls = 0;
      final retries = <int>[];
      final delays = <Duration>[];
      final result = await bindWhenAddressAvailable(
        bind: () async {
          if (++calls < 4) throw unavailable();
          return 'ready';
        },
        shouldStop: () => false,
        sleep: (duration) async {
          delays.add(duration);
        },
        onRetry: (_, attempt) => retries.add(attempt),
      );
      expect(result, 'ready');
      expect(calls, 4);
      expect(retries, [1, 2, 3]);
      expect(delays, List.filled(3, const Duration(seconds: 2)));
    },
  );

  for (final code in [98, 13, 1, 0]) {
    test('does not retry bind error $code or change the address', () async {
      var calls = 0;
      var slept = false;
      final error = SocketException('fatal', osError: OSError('fatal', code));
      await expectLater(
        bindWhenAddressAvailable<Object>(
          bind: () async {
            calls++;
            throw error;
          },
          shouldStop: () => false,
          sleep: (_) async {
            slept = true;
          },
        ),
        throwsA(same(error)),
      );
      expect(calls, 1);
      expect(slept, isFalse);
    });
  }

  test('non-socket exceptions remain fatal', () async {
    final error = StateError('bad TLS or configuration');
    await expectLater(
      bindWhenAddressAvailable<Object>(
        bind: () async => throw error,
        shouldStop: () => false,
      ),
      throwsA(same(error)),
    );
  });

  test('shutdown before binding opens no listener', () async {
    var calls = 0;
    expect(
      await bindWhenAddressAvailable(
        bind: () async {
          calls++;
          return 'listener';
        },
        shouldStop: () => true,
      ),
      isNull,
    );
    expect(calls, 0);
  });

  test('shutdown during retry prevents another bind', () async {
    var stopped = false;
    var calls = 0;
    expect(
      await bindWhenAddressAvailable<Object>(
        bind: () async {
          calls++;
          throw unavailable();
        },
        shouldStop: () => stopped,
        sleep: (_) async {
          stopped = true;
        },
      ),
      isNull,
    );
    expect(calls, 1);
  });

  test('rejects zero retry delay instead of busy-spinning', () async {
    await expectLater(
      bindWhenAddressAvailable(
        bind: () async => 'listener',
        shouldStop: () => false,
        retryDelay: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test(
    'network waiting still permits all twelve missing-motor announcements',
    () async {
      final voice = RecordingVoiceAnnouncer();
      final selfCheck = BootSelfCheck(
        voice: voice,
        config: const BootSelfCheckConfig(
          deadline: Duration(milliseconds: 10),
          pollInterval: Duration(milliseconds: 1),
        ),
      );
      final result = await selfCheck.run(
        CallbackBootSelfCheckProbe(() {
          final now = DateTime.now();
          return BootSelfCheckSnapshot(
            imu: ImuBootSnapshot(
              deviceOpen: true,
              hasFrame: true,
              finite: true,
              frameHz: 100,
              lastFrameAt: now,
            ),
            motors: [
              for (final leg in ['FR', 'FL', 'RR', 'RL'])
                for (final joint in ['Hip', 'Thigh', 'Calf', 'Foot'])
                  MotorBootSnapshot(
                    name: '$leg $joint',
                    hasReport: leg == 'FR',
                    finite: leg == 'FR',
                    hasError: leg != 'FR',
                    frameHz: leg == 'FR' ? 100 : 0,
                    lastFrameAt: leg == 'FR' ? now : null,
                  ),
            ],
            controller: const ControllerBootSnapshot(
              connected: true,
              hasFrame: true,
              frameHz: 50,
            ),
          );
        }),
      );
      expect(result.passed, isFalse);
      expect(selfCheck.canEnable, isFalse);
      final sleeping = Completer<void>();
      final enteredRetry = Completer<void>();
      var stopped = false;
      var networkFinished = false;
      final network =
          bindWhenAddressAvailable<Object>(
            bind: () async => throw unavailable(),
            shouldStop: () => stopped,
            sleep: (_) {
              enteredRetry.complete();
              return sleeping.future;
            },
          ).then((value) {
            networkFinished = true;
            return value;
          });
      await enteredRetry.future;
      await Future<void>.delayed(Duration.zero);
      expect(networkFinished, isFalse);
      expect(voice.announcements.length, 12);
      expect(voice.announcements.map((item) => item.audioAsset).toSet(), {
        for (final leg in ['fl', 'rr', 'rl'])
          for (final joint in ['hip', 'thigh', 'calf', 'foot'])
            'motor_signal_${leg}_${joint}_fault.wav',
      });
      expect(
        voice.announcements.any((a) => a.key == 'boot_self_check_passed'),
        isFalse,
      );
      expect(selfCheck.canEnable, isFalse);
      stopped = true;
      sleeping.complete();
      expect(await network, isNull);
    },
  );

  test(
    'real loopback listener can start after unavailable-address retries',
    () async {
      var calls = 0;
      final server = await bindWhenAddressAvailable<ServerSocket>(
        bind: () async {
          if (++calls < 3) throw unavailable();
          return ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        },
        shouldStop: () => false,
        sleep: (_) async {},
      );
      expect(calls, 3);
      expect(server, isNotNull);
      await server!.close();
    },
  );
}
