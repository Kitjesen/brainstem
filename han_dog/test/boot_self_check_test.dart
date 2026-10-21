import 'package:han_dog/src/app/boot_self_check.dart';
import 'package:han_dog/src/app/voice_announcer.dart';
import 'package:test/test.dart';

class RecordingVoiceAnnouncer implements VoiceAnnouncer {
  final announcements = <VoiceAnnouncement>[];

  @override
  Future<void> announce(VoiceAnnouncement announcement) async {
    announcements.add(announcement);
  }
}

BootSelfCheckSnapshot healthySnapshot({DateTime? now}) {
  final timestamp = now ?? DateTime.now();
  return BootSelfCheckSnapshot(
    imu: ImuBootSnapshot(
      deviceOpen: true,
      hasFrame: true,
      finite: true,
      frameHz: 100,
      lastFrameAt: timestamp,
    ),
    motors: [
      for (var i = 0; i < 16; i++)
        MotorBootSnapshot(
          name: 'motor-$i',
          hasReport: true,
          finite: true,
          hasError: false,
          frameHz: 100,
          lastFrameAt: timestamp,
        ),
    ],
    controller: const ControllerBootSnapshot(
      connected: true,
      hasFrame: true,
      frameHz: 50,
    ),
  );
}

void main() {
  test('healthy signals become ready and announce completion', () async {
    final voice = RecordingVoiceAnnouncer();
    final selfCheck = BootSelfCheck(
      voice: voice,
      config: const BootSelfCheckConfig(
        healthyWindow: Duration.zero,
        pollInterval: Duration.zero,
        deadline: Duration(milliseconds: 10),
      ),
    );

    final result = await selfCheck.run(
      CallbackBootSelfCheckProbe(() => healthySnapshot()),
    );

    expect(result.passed, isTrue);
    expect(selfCheck.canEnable, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(voice.announcements.single.key, 'boot_self_check_passed');
  });

  test(
    'faulted signals remain locked and identify the failed checks',
    () async {
      final voice = RecordingVoiceAnnouncer();
      final selfCheck = BootSelfCheck(
        voice: voice,
        config: const BootSelfCheckConfig(
          healthyWindow: Duration.zero,
          pollInterval: Duration.zero,
          deadline: Duration(milliseconds: 2),
        ),
      );

      final result = await selfCheck.run(
        CallbackBootSelfCheckProbe(
          () => BootSelfCheckSnapshot(
            imu: ImuBootSnapshot(
              deviceOpen: true,
              hasFrame: false,
              finite: true,
              frameHz: 0,
              lastFrameAt: null,
            ),
            motors: [
              const MotorBootSnapshot(
                name: 'FR Hip',
                hasReport: false,
                finite: false,
                hasError: true,
                frameHz: 0,
              ),
            ],
            controller: const ControllerBootSnapshot(
              connected: false,
              hasFrame: false,
              frameHz: 0,
            ),
          ),
        ),
      );

      expect(result.status, BootSelfCheckStatus.faulted);
      expect(selfCheck.canEnable, isFalse);
      expect(selfCheck.blockReason, contains('IMU信号异常'));
      expect(selfCheck.blockReason, contains('FR Hip'));
      expect(selfCheck.blockReason, contains('遥控器信号异常'));
      await Future<void>.delayed(Duration.zero);
      expect(
        voice.announcements.map((item) => item.key),
        containsAll(['imu_signal', 'motor_signal', 'controller_signal']),
      );
      expect(
        voice.announcements.map((item) => item.audioAsset),
        contains('motor_signal_fr_hip_fault.wav'),
      );

      final interlock = MotorEnableInterlock();
      var hardwareCalled = false;
      await expectLater(
        interlock.request(() async {
          hardwareCalled = true;
        }),
        throwsA(isA<StateError>()),
      );
      expect(hardwareCalled, isFalse);
    },
  );

  test(
    'a transient input fault must recover before the healthy window starts',
    () async {
      final voice = RecordingVoiceAnnouncer();
      var samples = 0;
      final selfCheck = BootSelfCheck(
        voice: voice,
        config: const BootSelfCheckConfig(
          healthyWindow: Duration.zero,
          pollInterval: Duration.zero,
          deadline: Duration(milliseconds: 20),
        ),
      );

      final result = await selfCheck.run(
        CallbackBootSelfCheckProbe(() {
          samples++;
          if (samples == 1) {
            final healthy = healthySnapshot();
            return BootSelfCheckSnapshot(
              imu: const ImuBootSnapshot(
                deviceOpen: true,
                hasFrame: false,
                finite: true,
                frameHz: 0,
                lastFrameAt: null,
              ),
              motors: healthy.motors,
              controller: healthy.controller,
            );
          }
          return healthySnapshot();
        }),
      );

      expect(result.passed, isTrue);
      expect(samples, greaterThan(1));
      expect(voice.announcements.single.key, 'boot_self_check_passed');
    },
  );

  test('controller-only fault does not block motor enable', () async {
    final voice = RecordingVoiceAnnouncer();
    final healthy = healthySnapshot();
    final selfCheck = BootSelfCheck(
      voice: voice,
      config: const BootSelfCheckConfig(
        healthyWindow: Duration.zero,
        pollInterval: Duration.zero,
        deadline: Duration(milliseconds: 2),
      ),
    );

    final result = await selfCheck.run(
      CallbackBootSelfCheckProbe(
        () => BootSelfCheckSnapshot(
          imu: healthy.imu,
          motors: healthy.motors,
          controller: const ControllerBootSnapshot(
            connected: false,
            hasFrame: false,
            frameHz: 0,
          ),
        ),
      ),
    );

    expect(result.status, BootSelfCheckStatus.faulted);
    expect(result.motorEnableAllowed, isTrue);
    expect(selfCheck.canEnable, isTrue);
    expect(selfCheck.blockReason, contains('遥控器信号异常'));
    await Future<void>.delayed(Duration.zero);
    expect(
      voice.announcements.single.text,
      '遥控器信号异常，请检查遥控器是否打开',
    );

    final interlock = MotorEnableInterlock()..permit();
    var hardwareCalled = false;
    await interlock.request(() async {
      hardwareCalled = true;
    });
    expect(hardwareCalled, isTrue);
  });
}
