import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

final _log = Logger('han_dog.voice');

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

/// Production uses ALSA only when a prompt directory is explicitly configured.
/// Without it, local tests and development runs remain dry-run and dependency-free.
VoiceAnnouncer createVoiceAnnouncerFromEnvironment() {
  final directory = Platform.environment['HAN_DOG_VOICE_DIR'];
  if (directory == null || directory.isEmpty) {
    return const LoggingVoiceAnnouncer();
  }
  return SafeVoiceAnnouncer(
    primary: AlsaVoiceAnnouncer(
      audioDirectory: directory,
      device:
          Platform.environment['HAN_DOG_VOICE_DEVICE'] ??
          'plughw:CARD=BT67,DEV=0',
    ),
    fallback: const LoggingVoiceAnnouncer(),
  );
}
