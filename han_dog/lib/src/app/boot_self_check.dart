import 'dart:async';

import 'package:logging/logging.dart';

import 'voice_announcer.dart';

final _log = Logger('han_dog.boot_self_check');

enum BootSelfCheckStatus { locked, checking, ready, faulted }

class BootSelfCheckConfig {
  final Duration healthyWindow;
  final Duration pollInterval;
  final Duration deadline;
  final Duration imuMaxAge;
  final Duration motorMaxAge;
  final int minimumImuHz;
  final int minimumMotorHz;
  final int minimumControllerHz;
  final int expectedMotorCount;

  const BootSelfCheckConfig({
    this.healthyWindow = const Duration(milliseconds: 350),
    this.pollInterval = const Duration(milliseconds: 20),
    this.deadline = const Duration(seconds: 3),
    this.imuMaxAge = const Duration(milliseconds: 200),
    this.motorMaxAge = const Duration(milliseconds: 250),
    this.minimumImuHz = 0,
    this.minimumMotorHz = 0,
    this.minimumControllerHz = 0,
    this.expectedMotorCount = 16,
  });
}

class ImuBootSnapshot {
  final bool deviceOpen;
  final bool hasFrame;
  final bool finite;
  final int frameHz;
  final DateTime? lastFrameAt;

  const ImuBootSnapshot({
    required this.deviceOpen,
    required this.hasFrame,
    required this.finite,
    required this.frameHz,
    required this.lastFrameAt,
  });
}

class MotorBootSnapshot {
  final String name;
  final bool hasReport;
  final bool finite;
  final bool hasError;
  final int frameHz;
  final DateTime? lastFrameAt;

  const MotorBootSnapshot({
    required this.name,
    required this.hasReport,
    required this.finite,
    required this.hasError,
    required this.frameHz,
    this.lastFrameAt,
  });
}

class ControllerBootSnapshot {
  final bool connected;
  final bool hasFrame;
  final int frameHz;

  const ControllerBootSnapshot({
    required this.connected,
    required this.hasFrame,
    required this.frameHz,
  });
}

class BootSelfCheckSnapshot {
  final ImuBootSnapshot imu;
  final List<MotorBootSnapshot> motors;
  final ControllerBootSnapshot controller;

  const BootSelfCheckSnapshot({
    required this.imu,
    required this.motors,
    required this.controller,
  });
}

abstract interface class BootSelfCheckProbe {
  BootSelfCheckSnapshot sample();
}

class CallbackBootSelfCheckProbe implements BootSelfCheckProbe {
  final BootSelfCheckSnapshot Function() callback;

  const CallbackBootSelfCheckProbe(this.callback);

  @override
  BootSelfCheckSnapshot sample() => callback();
}

class BootSelfCheckFailure {
  final String key;
  final String text;
  final String audioAsset;

  const BootSelfCheckFailure({
    required this.key,
    required this.text,
    required this.audioAsset,
  });
}

class BootSelfCheckResult {
  final BootSelfCheckStatus status;
  final Duration elapsed;
  final List<BootSelfCheckFailure> failures;

  const BootSelfCheckResult({
    required this.status,
    required this.elapsed,
    this.failures = const [],
  });

  bool get passed => status == BootSelfCheckStatus.ready;

  /// A missing controller is recoverable after the operator powers it on.
  /// IMU, motor, and timeout failures remain enable-blocking.
  bool get motorEnableAllowed =>
      passed ||
      (status == BootSelfCheckStatus.faulted &&
          _controllerOnlyFaults(failures));
}

bool _controllerOnlyFaults(Iterable<BootSelfCheckFailure> failures) =>
    failures.isNotEmpty &&
    failures.every((failure) => failure.key == 'controller_signal');

/// Boot-time gate. A failed process stays locked until the next process boot.
class BootSelfCheck {
  final VoiceAnnouncer voice;
  final BootSelfCheckConfig config;
  final DateTime Function() clock;
  final Future<void> Function(Duration) sleep;

  BootSelfCheckStatus status = BootSelfCheckStatus.locked;
  List<BootSelfCheckFailure> lastFailures = const [];

  BootSelfCheck({
    required this.voice,
    this.config = const BootSelfCheckConfig(),
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  }) : clock = clock ?? DateTime.now,
       sleep = sleep ?? Future<void>.delayed;

  bool get canEnable =>
      status == BootSelfCheckStatus.ready ||
      (status == BootSelfCheckStatus.faulted &&
          _controllerOnlyFaults(lastFailures));

  String? get blockReason {
    if (status == BootSelfCheckStatus.ready) return null;
    if (lastFailures.isEmpty) return '开机自检未完成';
    return lastFailures.map((failure) => failure.text).join('; ');
  }

  Future<BootSelfCheckResult> run(BootSelfCheckProbe probe) async {
    status = BootSelfCheckStatus.checking;
    lastFailures = const [];
    final stopwatch = Stopwatch()..start();
    Duration? healthySince;

    while (stopwatch.elapsed < config.deadline) {
      BootSelfCheckSnapshot snapshot;
      try {
        snapshot = probe.sample();
      } catch (error, stackTrace) {
        _log.severe('Boot self-check probe failed', error, stackTrace);
        snapshot = _emptySnapshot();
      }

      final failures = _failures(snapshot);
      if (failures.isEmpty) {
        healthySince ??= stopwatch.elapsed;
        if (stopwatch.elapsed - healthySince >= config.healthyWindow) {
          status = BootSelfCheckStatus.ready;
          lastFailures = const [];
          final result = BootSelfCheckResult(
            status: status,
            elapsed: stopwatch.elapsed,
          );
          _log.info(
            'Boot self-check passed in ${result.elapsed.inMilliseconds}ms',
          );
          unawaited(
            _announce(
              const VoiceAnnouncement(
                key: 'boot_self_check_passed',
                text: '开机自检已完成',
                audioAsset: 'boot_self_check_passed.wav',
              ),
            ),
          );
          return result;
        }
      } else {
        healthySince = null;
        lastFailures = failures;
      }

      await sleep(config.pollInterval);
    }

    status = BootSelfCheckStatus.faulted;
    if (lastFailures.isEmpty) {
      lastFailures = [
        const BootSelfCheckFailure(
          key: 'self_check_timeout',
          text: '开机自检超时，请检查',
          audioAsset: 'boot_self_check_timeout.wav',
        ),
      ];
    }
    final result = BootSelfCheckResult(
      status: status,
      elapsed: stopwatch.elapsed,
      failures: List.unmodifiable(lastFailures),
    );
    if (result.motorEnableAllowed) {
      _log.warning(
        'Boot self-check found a recoverable controller fault; '
        'motor enable remains permitted: '
        '${lastFailures.map((failure) => failure.text).join("; ")}',
      );
    } else {
      _log.severe(
        'Boot self-check failed; motor enable remains blocked: '
        '${lastFailures.map((failure) => failure.text).join("; ")}',
      );
    }
    // Do not hold the control bootstrap on speaker playback or an ALSA
    // timeout. The lock is already faulted before announcements start.
    unawaited(_announceFaults(lastFailures));
    return result;
  }

  List<BootSelfCheckFailure> _failures(BootSelfCheckSnapshot snapshot) {
    final failures = <BootSelfCheckFailure>[];
    final imu = snapshot.imu;
    final imuFresh =
        imu.lastFrameAt != null &&
        clock().difference(imu.lastFrameAt!).abs() <= config.imuMaxAge;
    if (!imu.deviceOpen ||
        !imu.hasFrame ||
        !imu.finite ||
        imu.frameHz < config.minimumImuHz ||
        !imuFresh) {
      failures.add(
        const BootSelfCheckFailure(
          key: 'imu_signal',
          text: 'IMU信号异常，请检查',
          audioAsset: 'imu_signal_fault.wav',
        ),
      );
    }

    final badMotors = snapshot.motors
        .where(
          (motor) =>
              !motor.hasReport ||
              !motor.finite ||
              motor.hasError ||
              motor.frameHz < config.minimumMotorHz ||
              motor.lastFrameAt == null ||
              clock().difference(motor.lastFrameAt!).abs() > config.motorMaxAge,
        )
        .toList();
    final missingMotorCount =
        config.expectedMotorCount - snapshot.motors.length;
    if (missingMotorCount > 0) {
      badMotors.addAll([
        for (var i = 0; i < missingMotorCount; i++)
          MotorBootSnapshot(
            name: 'unknown motor ${snapshot.motors.length + i + 1}',
            hasReport: false,
            finite: false,
            hasError: true,
            frameHz: 0,
          ),
      ]);
    }
    if (badMotors.isNotEmpty) {
      for (final motor in badMotors) {
        final assetKey = _motorVoiceAssetKey(motor.name);
        failures.add(
          BootSelfCheckFailure(
            key: 'motor_signal',
            text: '${motor.name}电机信号异常，请检查',
            audioAsset: 'motor_signal_${assetKey}_fault.wav',
          ),
        );
      }
    }

    final controller = snapshot.controller;
    if (!controller.connected ||
        !controller.hasFrame ||
        controller.frameHz < config.minimumControllerHz) {
      failures.add(
        const BootSelfCheckFailure(
          key: 'controller_signal',
          text: '遥控器信号异常，请检查遥控器是否打开',
          audioAsset: 'controller_signal_fault.wav',
        ),
      );
    }
    return failures;
  }

  String _motorVoiceAssetKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<void> _announceFaults(List<BootSelfCheckFailure> failures) async {
    for (final failure in failures) {
      await _announce(
        VoiceAnnouncement(
          key: failure.key,
          text: failure.text,
          audioAsset: failure.audioAsset,
          priority: VoicePriority.fault,
        ),
      );
    }
  }

  Future<void> _announce(VoiceAnnouncement announcement) async {
    try {
      await voice.announce(announcement);
    } catch (error, stackTrace) {
      _log.warning(
        'Voice announcement failed: ${announcement.key}',
        error,
        stackTrace,
      );
    }
  }

  static BootSelfCheckSnapshot _emptySnapshot() => BootSelfCheckSnapshot(
    imu: ImuBootSnapshot(
      deviceOpen: false,
      hasFrame: false,
      finite: false,
      frameHz: 0,
      lastFrameAt: null,
    ),
    motors: const [],
    controller: const ControllerBootSnapshot(
      connected: false,
      hasFrame: false,
      frameHz: 0,
    ),
  );
}

/// Shared gate for both H-enable and gRPC enable paths.
class MotorEnableInterlock {
  bool _allowed = false;
  String _reason = '开机自检未完成';

  bool get allowed => _allowed;
  String get reason => _reason;

  void permit() {
    _allowed = true;
    _reason = '';
  }

  void block(String reason) {
    _allowed = false;
    _reason = reason;
  }

  Future<void> request(Future<void> Function() hardwareEnable) async {
    if (!_allowed) {
      throw StateError('Motor enable blocked: \$_reason');
    }
    await hardwareEnable();
    if (!_allowed) {
      throw StateError(
        'Motor enable blocked after hardware request: \$_reason',
      );
    }
  }
}
