import 'dart:async';

import 'package:thunder/src/app/voice_announcer.dart';
import 'package:test/test.dart';

class CallbackVoice implements VoiceAnnouncer {
  final Future<void> Function(VoiceAnnouncement) callback;
  CallbackVoice(this.callback);
  @override
  Future<void> announce(VoiceAnnouncement announcement) =>
      callback(announcement);
}

VoiceAnnouncement message(String id) =>
    VoiceAnnouncement(key: id, text: id, audioAsset: '$id.wav');

void main() {
  test('shared transport runs one playback at a time in FIFO order', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final calls = <String>[];
    final voice = QueuedVoiceAnnouncer(
      CallbackVoice((a) {
        calls.add(a.key);
        return a.key == 'first' ? first.future : second.future;
      }),
    );
    final a = voice.announce(message('first'));
    final b = voice.announce(message('second'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first']);
    first.complete();
    await a;
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first', 'second']);
    second.complete();
    await b;
  });

  test('failed playback does not poison the following announcement', () async {
    final calls = <String>[];
    final voice = QueuedVoiceAnnouncer(
      CallbackVoice((a) async {
        calls.add(a.key);
        if (a.key == 'bad') throw StateError('missing speaker');
      }),
    );
    final failed = expectLater(
      voice.announce(message('bad')),
      throwsStateError,
    );
    await voice.announce(message('good'));
    await failed;
    expect(calls, ['bad', 'good']);
  });

  test('queue is bounded and rejects overflow without starting it', () async {
    final release = Completer<void>();
    final calls = <String>[];
    final voice = QueuedVoiceAnnouncer(
      CallbackVoice((a) {
        calls.add(a.key);
        return release.future;
      }),
    );
    final pending = [for (var i = 0; i < 8; i++) voice.announce(message('$i'))];
    await expectLater(voice.announce(message('overflow')), throwsStateError);
    release.complete();
    await Future.wait(pending);
    expect(calls.length, 8);
    expect(calls, isNot(contains('overflow')));
  });
}
