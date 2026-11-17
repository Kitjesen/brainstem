import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

final _log = Logger('thunder.voice');

enum VoicePriority { normal, fault }

/// A logical announcement. Backends may render [audioAsset] in different ways.
class VoiceAnnouncement {
  final String key;
  final String text;
  final String audioAsset;
  final VoicePriority priority;

  const VoiceAnnouncement({
    required this.key,
    required this.text,
    required this.audioAsset,
    this.priority = VoicePriority.normal,
  });
}

/// Replaceable speech/output boundary. The self-check does not depend on ALSA.
abstract interface class VoiceAnnouncer {
  Future<void> announce(VoiceAnnouncement announcement);
}

/// Development backend. It preserves the event and keeps tests hardware-free.
class LoggingVoiceAnnouncer implements VoiceAnnouncer {
  const LoggingVoiceAnnouncer();

  @override
  Future<void> announce(VoiceAnnouncement announcement) async {
    _log.info(
      'VOICE_DRY_RUN key=${announcement.key} text=${announcement.text} '
      'asset=${announcement.audioAsset}',
    );
  }
}

/// Minimal Linux backend for pre-recorded WAV prompts.
///
/// Audio is intentionally selected by a logical asset name rather than an
/// absolute path so the prompt directory can be replaced independently.
class AlsaVoiceAnnouncer implements VoiceAnnouncer {
  final String audioDirectory;
  final String device;
  final String player;
  final Duration timeout;

  const AlsaVoiceAnnouncer({
    required this.audioDirectory,
    this.device = 'plughw:CARD=BT67,DEV=0',
    this.player = 'aplay',
    this.timeout = const Duration(seconds: 5),
  });

  @override
  Future<void> announce(VoiceAnnouncement announcement) async {
    final path = File(
      '$audioDirectory${Platform.pathSeparator}${announcement.audioAsset}',
    );
    if (!path.existsSync()) {
      throw FileSystemException('Voice asset not found', path.path);
    }

    final process = await Process.start(player, [
      '-q',
      '-D',
      device,
      path.path,
    ]);
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      if (exitCode != 0) {
        throw ProcessException(
          player,
          ['-q', '-D', device, path.path],
          'aplay exited with code $exitCode',
          exitCode,
        );
      }
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      rethrow;
    }
  }
}

/// Uses the validated Linux sender instead of treating the ESP32 as a sound card.
class Esp32VoiceAnnouncer implements VoiceAnnouncer {
  final String senderScript;
  final String pythonExecutable;
  final Duration timeout;

  const Esp32VoiceAnnouncer({
    required this.senderScript,
    this.pythonExecutable = 'python3',
    this.timeout = const Duration(seconds: 30),
  });

  String _clipFor(VoiceAnnouncement announcement) {
    if (announcement.key == 'profile_switched') {
      const modes = {
        'mode_flat.wav': 'mode_flat',
        'mode_stairs.wav': 'mode_stairs',
        'profile_changed.wav': 'profile_changed',
      };
      final clip = modes[announcement.audioAsset];
      if (clip != null) return clip;
    }
    if (announcement.key == 'boot_self_check_passed' &&
        announcement.audioAsset == 'boot_self_check_passed.wav') {
      return 'selfcheck';
    }
    if (announcement.key == 'motor_signal') {
      for (final leg in ['fl', 'fr', 'rl', 'rr']) {
        for (final joint in ['hip', 'thigh', 'calf', 'foot']) {
          if (announcement.audioAsset ==
              'motor_signal_${leg}_${joint}_fault.wav') {
            return '${leg}_${joint}_fault';
          }
        }
      }
      if (RegExp(
        r'^motor_signal_unknown_motor_([1-9]|1[0-6])_fault\.wav$',
      ).hasMatch(announcement.audioAsset)) {
        return 'unknown_motor_fault';
      }
    }
    if (announcement.key == 'imu_signal' &&
        announcement.audioAsset == 'imu_signal_fault.wav') {
      return 'imu_fault';
    }
    if (announcement.key == 'controller_signal' &&
        announcement.audioAsset == 'controller_signal_fault.wav') {
      return 'controller_fault';
    }
    throw UnsupportedError(
      'No ESP32 clip for ${announcement.key}: ${announcement.audioAsset}',
    );
  }

  @override
  Future<void> announce(VoiceAnnouncement announcement) async {
    final clip = _clipFor(announcement);
    if (!File(senderScript).existsSync()) {
      throw FileSystemException('ESP32 voice sender not found', senderScript);
    }
    final arguments = [senderScript, clip];
    final process = await Process.start(
      pythonExecutable,
      arguments,
      runInShell: false,
    );
    final output = Future.wait([
      process.stdout.drain<void>(),
      process.stderr.drain<void>(),
    ]);
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      if (exitCode != 0) {
        throw ProcessException(
          pythonExecutable,
          arguments,
          'ESP32 voice sender exited with code $exitCode',
          exitCode,
        );
      }
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      rethrow;
    } finally {
      await output;
    }
  }
}

/// Serialize the shared USB transport without blocking a control transaction.
class QueuedVoiceAnnouncer implements VoiceAnnouncer {
  final VoiceAnnouncer primary;
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  QueuedVoiceAnnouncer(this.primary);

  @override
  Future<void> announce(VoiceAnnouncement announcement) {
    if (_pending >= 8) {
      return Future<void>.error(
        StateError('Voice queue full; announcement dropped'),
      );
    }
    _pending++;
    final operation = _tail.then((_) => primary.announce(announcement));
    _tail = operation
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending--);
    return operation;
  }
}

/// Keeps a logging fallback so a missing speaker/asset never changes safety.
class SafeVoiceAnnouncer implements VoiceAnnouncer {
  final VoiceAnnouncer primary;
  final VoiceAnnouncer fallback;

  const SafeVoiceAnnouncer({required this.primary, required this.fallback});

  @override
  Future<void> announce(VoiceAnnouncement announcement) async {
    try {
      await primary.announce(announcement);
    } catch (error, stackTrace) {
      _log.warning(
        'Voice output failed for ${announcement.key}',
        error,
        stackTrace,
      );
      await fallback.announce(announcement);
    }
  }
}

/// ESP32 is opt-in; otherwise preserve the existing ALSA/logging selection.
/// Without output configuration, development runs remain dry-run.
VoiceAnnouncer createVoiceAnnouncerFromEnvironment({
  Map<String, String>? environment,
}) {
  final config = environment ?? Platform.environment;
  if (config['THUNDER_VOICE_BACKEND']?.trim().toLowerCase() == 'esp32') {
    final sender = config['THUNDER_VOICE_ESP32_SENDER'];
    if (sender == null || sender.trim().isEmpty) {
      _log.warning('ESP32 voice sender is not configured; using logging');
      return const LoggingVoiceAnnouncer();
    }
    return SafeVoiceAnnouncer(
      primary: Esp32VoiceAnnouncer(
        senderScript: sender,
        pythonExecutable: config['THUNDER_VOICE_PYTHON'] ?? 'python3',
      ),
      fallback: const LoggingVoiceAnnouncer(),
    );
  }
  final directory = config['THUNDER_VOICE_DIR'];
  if (directory == null || directory.isEmpty) {
    return const LoggingVoiceAnnouncer();
  }
  return SafeVoiceAnnouncer(
    primary: AlsaVoiceAnnouncer(
      audioDirectory: directory,
      device: config['THUNDER_VOICE_DEVICE'] ?? 'plughw:CARD=BT67,DEV=0',
    ),
    fallback: const LoggingVoiceAnnouncer(),
  );
}
