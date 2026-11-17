import 'dart:async';
import 'dart:convert';
import 'package:thunder/src/real_controller.dart';

Future<void> main() async {
  final receiver = RealController('/dev/yunzhuo');
  var frames = 0;
  Object? error;
  List<int>? latest;
  List<int>? minimum;
  List<int>? maximum;
  final perSecond = <int>[];
  final subscription = receiver.stateStream.listen((state) {
    frames++;
    latest = List<int>.of(state.rawChannels);
    minimum ??= List<int>.of(state.rawChannels);
    maximum ??= List<int>.of(state.rawChannels);
    for (var i = 0; i < state.rawChannels.length; i++) {
      if (state.rawChannels[i] < minimum![i]) minimum![i] = state.rawChannels[i];
      if (state.rawChannels[i] > maximum![i]) maximum![i] = state.rawChannels[i];
    }
  }, onError: (Object e) { error = e; });
  final opened = receiver.open();
  if (opened) {
    var previous = 0;
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      perSecond.add(frames - previous);
      previous = frames;
    });
    await Future<void>.delayed(const Duration(seconds: 16));
    timer.cancel();
  }
  await subscription.cancel();
  receiver.dispose();
  print(jsonEncode({'opened': opened, 'frames': frames, 'perSecond': perSecond,
    'channels': latest, 'minimum': minimum, 'maximum': maximum,
    'error': error?.toString(), 'motorObjectsCreated': false}));
}
