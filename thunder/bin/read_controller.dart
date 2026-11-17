import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:thunder/src/real_controller.dart';

({String port, int seconds}) parseOptions(List<String> args) {
  if (args.length > 2) {
    throw const FormatException(
      'Usage: read_controller [port] [seconds:1..60]',
    );
  }
  final seconds = args.length > 1 ? int.tryParse(args[1]) : 5;
  if (seconds == null || seconds < 1 || seconds > 60) {
    throw const FormatException('Seconds must be between 1 and 60');
  }
  final port = args.isNotEmpty ? args.first : '/dev/yunzhuo';
  if (port.trim().isEmpty) {
    throw const FormatException('Port must not be empty');
  }
  return (port: port, seconds: seconds);
}

Future<void> main(List<String> args) async {
  final ({String port, int seconds}) options;
  try {
    options = parseOptions(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exit(2);
  }
  final controller = RealController(options.port);
  var frames = 0;
  List<int>? latest;
  List<int>? minimum;
  List<int>? maximum;
  Object? readError;
  final subscription = controller.stateStream.listen(
    (state) {
      final channels = state.rawChannels;
      frames++;
      latest = List<int>.of(channels);
      minimum ??= List<int>.of(channels);
      maximum ??= List<int>.of(channels);
      for (var i = 0; i < channels.length; i++) {
        if (channels[i] < minimum![i]) minimum![i] = channels[i];
        if (channels[i] > maximum![i]) maximum![i] = channels[i];
      }
    },
    onError: (Object error, StackTrace stack) {
      readError = error;
      stderr.writeln('$error\n$stack');
    },
  );
  var opened = false;
  try {
    opened = controller.open();
    if (opened) await Future<void>.delayed(Duration(seconds: options.seconds));
  } finally {
    await subscription.cancel();
    controller.dispose();
  }
  stdout.writeln(
    jsonEncode({
      'port': options.port,
      'seconds': options.seconds,
      'opened': opened,
      'healthyFrames': frames,
      'channels': latest,
      'minimum': minimum,
      'maximum': maximum,
      'readError': readError?.toString(),
      'motorObjectsCreated': false,
    }),
  );
  exit(opened && frames > 0 && readError == null ? 0 : 1);
}
