import 'dart:io';

import 'package:thunder/src/app/voice_announcer.dart';
import 'package:test/test.dart';

class RecordingVoiceAnnouncer implements VoiceAnnouncer {
  final announcements = <VoiceAnnouncement>[];

  @override
  Future<void> announce(VoiceAnnouncement announcement) async {
    announcements.add(announcement);
  }
}

const selfCheck = VoiceAnnouncement(
  key: 'boot_self_check_passed',
  text: 'Self-check passed',
  audioAsset: 'boot_self_check_passed.wav',
);

void main() {
  late Directory temporary;
  late File sender;
  late File arguments;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('voice_announcer_test_');
    // Spaces also exercise argument boundaries without involving a shell.
    sender = File('${temporary.path}/fake sender.dart');
    arguments = File('${temporary.path}/args.txt');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<void> writeSender([String body = '']) async {
    await sender.writeAsString('''
import 'dart:io';

Future<void> main(List<String> args) async {
  File.fromUri(Platform.script.resolve('args.txt'))
      .writeAsStringSync(args.join('\\n'));
  $body
}
''');
  }

  Esp32VoiceAnnouncer announcer({
    Duration timeout = const Duration(seconds: 10),
  }) {
    return Esp32VoiceAnnouncer(
      senderScript: sender.path,
      pythonExecutable: Platform.resolvedExecutable,
      timeout: timeout,
    );
  }

  test('ESP32 constructor preserves configuration and defaults', () {
    const defaults = Esp32VoiceAnnouncer(senderScript: 'sender.py');
    expect(defaults.senderScript, 'sender.py');
    expect(defaults.pythonExecutable, 'python3');
    expect(defaults.timeout, const Duration(seconds: 30));

    final configured = announcer(timeout: const Duration(seconds: 2));
    expect(configured.senderScript, sender.path);
    expect(configured.pythonExecutable, Platform.resolvedExecutable);
    expect(configured.timeout, const Duration(seconds: 2));
  });

  test('self-check sends only the selfcheck clip', () async {
    await writeSender();
    await announcer().announce(selfCheck);
    expect(await arguments.readAsLines(), ['selfcheck']);
  });

  for (final clip in ['mode_flat', 'mode_stairs', 'profile_changed']) {
    test('$clip requires an exact committed-profile event', () async {
      await writeSender();
      await announcer().announce(
        VoiceAnnouncement(
          key: 'profile_switched',
          text: 'Committed',
          audioAsset: '$clip.wav',
        ),
      );
      expect(await arguments.readAsLines(), [clip]);
      await expectLater(
        announcer().announce(
          VoiceAnnouncement(
            key: 'profile_requested',
            text: 'Not committed',
            audioAsset: '$clip.wav',
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  }

  for (final leg in ['fl', 'fr', 'rl', 'rr']) {
    for (final joint in ['hip', 'thigh', 'calf', 'foot']) {
      test('$leg $joint fault sends its exact clip', () async {
        await writeSender();
        await announcer().announce(
          VoiceAnnouncement(
            key: 'motor_signal',
            text: '$leg $joint fault',
            audioAsset: 'motor_signal_${leg}_${joint}_fault.wav',
            priority: VoicePriority.fault,
          ),
        );
        expect(await arguments.readAsLines(), ['${leg}_${joint}_fault']);
      });
    }
  }

  for (final entry in {
    'imu_signal': ['imu_signal_fault.wav', 'imu_fault'],
    'controller_signal': ['controller_signal_fault.wav', 'controller_fault'],
    'motor_signal': [
      'motor_signal_unknown_motor_16_fault.wav',
      'unknown_motor_fault',
    ],
  }.entries) {
    test('${entry.key} preserves its diagnostic identity', () async {
      await writeSender();
      await announcer().announce(
        VoiceAnnouncement(
          key: entry.key,
          text: 'Fault',
          audioAsset: entry.value[0],
        ),
      );
      expect(await arguments.readAsLines(), [entry.value[1]]);
    });
  }

  final rejected = <String, List<String>>{
    'self-check key with wrong asset': ['boot_self_check_passed', 'other.wav'],
    'self-check asset with wrong key': ['other', 'boot_self_check_passed.wav'],
    'motor asset with wrong key': ['other', 'motor_signal_fl_hip_fault.wav'],
    'motor key with self-check asset': [
      'motor_signal',
      'boot_self_check_passed.wav',
    ],
    'IMU wrong key': ['motor_signal', 'imu_signal_fault.wav'],
    'controller wrong key': ['imu_signal', 'controller_signal_fault.wav'],
    'parent traversal': ['motor_signal', '../motor_signal_fl_hip_fault.wav'],
    'backslash traversal': [
      'motor_signal',
      r'..\motor_signal_fl_hip_fault.wav',
    ],
    'absolute path': ['motor_signal', '/tmp/motor_signal_fl_hip_fault.wav'],
    'asset suffix': ['motor_signal', 'motor_signal_fl_hip_fault.wav.bak'],
    'all-leg fault': ['motor_signal', 'motor_signal_fault.wav'],
    'unknown leg': ['motor_signal', 'motor_signal_xx_hip_fault.wav'],
    'unknown joint': ['motor_signal', 'motor_signal_fl_knee_fault.wav'],
    'unknown index zero': [
      'motor_signal',
      'motor_signal_unknown_motor_0_fault.wav',
    ],
    'unknown index overflow': [
      'motor_signal',
      'motor_signal_unknown_motor_17_fault.wav',
    ],
  };

  for (final entry in rejected.entries) {
    test('rejects ${entry.key} without starting the sender', () async {
      await writeSender();
      final announcement = VoiceAnnouncement(
        key: entry.value[0],
        text: 'Unsupported announcement',
        audioAsset: entry.value[1],
      );
      // Future.sync also captures a synchronous validation failure.
      await expectLater(
        Future.sync(() => announcer().announce(announcement)),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await arguments.exists(), isFalse);
    });
  }

  test(
    'nonzero child exit propagates and Safe invokes recording fallback',
    () async {
      await writeSender('exitCode = 23;');
      final primary = announcer();
      await expectLater(primary.announce(selfCheck), throwsA(anything));
      expect(await arguments.readAsLines(), ['selfcheck']);

      final fallback = RecordingVoiceAnnouncer();
      await SafeVoiceAnnouncer(
        primary: primary,
        fallback: fallback,
      ).announce(selfCheck);
      expect(fallback.announcements, [same(selfCheck)]);
    },
  );

  test('drains large stdout and stderr without deadlocking', () async {
    await writeSender('''
  final chunk = List<int>.filled(65536, 120);
  for (var i = 0; i < 32; i++) {
    stdout.add(chunk);
    stderr.add(chunk);
  }
  await stdout.flush();
  await stderr.flush();
''');
    await announcer().announce(selfCheck);
    expect(await arguments.readAsLines(), ['selfcheck']);
  });

  test(
    'timeout kills and reaps a child that ignores SIGTERM',
    () async {
      final pidFile = File('${temporary.path}/pid.txt');
      final termFile = File('${temporary.path}/term.txt');
      await writeSender('''
  ProcessSignal.sigterm.watch().listen((_) {
    File.fromUri(Platform.script.resolve('term.txt')).writeAsStringSync('term');
  });
  File.fromUri(Platform.script.resolve('pid.txt')).writeAsStringSync('\$pid');
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
''');
      addTearDown(() async {
        if (await pidFile.exists()) {
          final childPid = int.parse(await pidFile.readAsString());
          if (await Directory('/proc/$childPid').exists()) {
            Process.killPid(childPid, ProcessSignal.sigkill);
          }
        }
      });

      await expectLater(
        announcer(timeout: const Duration(seconds: 5)).announce(selfCheck),
        throwsA(isA<Exception>()),
      );
      expect(
        await pidFile.exists(),
        isTrue,
        reason: 'Child must reach its hang',
      );
      final childPid = int.parse(await pidFile.readAsString());
      expect(
        await termFile.exists(),
        isTrue,
        reason: 'SIGTERM must precede SIGKILL',
      );
      expect(
        await Directory('/proc/$childPid').exists(),
        isFalse,
        reason: 'announce must reap the timed-out child before returning',
      );
    },
    skip: !Platform.isLinux,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'factory without a backend preserves logging and legacy ALSA selection',
    () {
      expect(
        createVoiceAnnouncerFromEnvironment(environment: {}),
        isA<LoggingVoiceAnnouncer>(),
      );
      expect(
        createVoiceAnnouncerFromEnvironment(
          environment: {'THUNDER_VOICE_DIR': ''},
        ),
        isA<LoggingVoiceAnnouncer>(),
      );

      final legacy =
          createVoiceAnnouncerFromEnvironment(
                environment: {
                  'THUNDER_VOICE_DIR': '/unused/prompts',
                  'THUNDER_VOICE_DEVICE': 'test-device',
                },
              )
              as SafeVoiceAnnouncer;
      expect(legacy.fallback, isA<LoggingVoiceAnnouncer>());
      final alsa = legacy.primary as AlsaVoiceAnnouncer;
      expect(alsa.audioDirectory, '/unused/prompts');
      expect(alsa.device, 'test-device');
      expect(alsa.player, 'aplay');

      final defaults =
          createVoiceAnnouncerFromEnvironment(
                environment: {'THUNDER_VOICE_DIR': '/unused/prompts'},
              )
              as SafeVoiceAnnouncer;
      expect(
        (defaults.primary as AlsaVoiceAnnouncer).device,
        'plughw:CARD=BT67,DEV=0',
      );
    },
  );

  test('ESP32 factory requires explicit opt-in and a nonempty sender', () {
    for (final environment in <Map<String, String>>[
      {'THUNDER_VOICE_ESP32_SENDER': 'sender.py'},
      {'THUNDER_VOICE_BACKEND': 'esp32'},
      {
        'THUNDER_VOICE_BACKEND': 'esp32',
        'THUNDER_VOICE_ESP32_SENDER': '',
        'THUNDER_VOICE_DIR': '/unused/prompts',
      },
    ]) {
      expect(
        createVoiceAnnouncerFromEnvironment(environment: environment),
        isA<LoggingVoiceAnnouncer>(),
      );
    }

    final selected =
        createVoiceAnnouncerFromEnvironment(
              environment: {
                'THUNDER_VOICE_BACKEND': 'esp32',
                'THUNDER_VOICE_ESP32_SENDER': sender.path,
                'THUNDER_VOICE_DIR': '/unused/prompts',
              },
            )
            as SafeVoiceAnnouncer;
    expect(selected.fallback, isA<LoggingVoiceAnnouncer>());
    final esp32 = selected.primary as Esp32VoiceAnnouncer;
    expect(esp32.senderScript, sender.path);
    expect(esp32.pythonExecutable, 'python3');
  });

  test(
    'ESP32 factory honors the injected executable without real playback',
    () async {
      await writeSender();
      final selected =
          createVoiceAnnouncerFromEnvironment(
                environment: {
                  'THUNDER_VOICE_BACKEND': 'esp32',
                  'THUNDER_VOICE_ESP32_SENDER': sender.path,
                  'THUNDER_VOICE_PYTHON': Platform.resolvedExecutable,
                },
              )
              as SafeVoiceAnnouncer;
      expect(
        (selected.primary as Esp32VoiceAnnouncer).pythonExecutable,
        Platform.resolvedExecutable,
      );
      await selected.announce(selfCheck);
      expect(await arguments.readAsLines(), ['selfcheck']);
    },
  );
}
