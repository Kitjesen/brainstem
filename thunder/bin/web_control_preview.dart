import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:thunder/src/real_control_dog.dart' show shapeSignedCommand;
import 'package:thunder/src/web_controller.dart';

/// Fake sensors and fake actuators only. This entry never opens robot devices.
Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln('web_control_preview.dart [--host=127.0.0.1] [--port=8088]');
    stdout.writeln(
      'Preview only; THUNDER_WEB_PREVIEW_TOKEN sets its login token.',
    );
    return;
  }
  var host = '127.0.0.1';
  var port = 8088;
  for (final arg in args) {
    if (arg.startsWith('--host=')) {
      host = arg.substring(7);
    } else if (arg.startsWith('--port=')) {
      port = int.parse(arg.substring(7));
    } else {
      throw ArgumentError('Unknown argument: $arg');
    }
  }
  final token =
      Platform.environment['THUNDER_WEB_PREVIEW_TOKEN'] ??
      base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256)));
  final slots =
      jsonDecode(File('thunder/config/operator_modes.json').readAsStringSync())
          as Map<String, dynamic>;
  final profiles = <String, Map<String, dynamic>>{
    for (final entry in slots.entries)
      entry.key:
          jsonDecode(
                File('thunder/profiles/${entry.value}.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
  };
  var slot = 'flat';
  var cms = 'GROUNDED';
  var enabled = false;
  var l1 = false;
  var command = [0.0, 0.0, 0.0];
  var positions = List<double>.filled(16, 0);
  var zeroCount = 0;
  var hardStopCount = 0;
  var inputCount = 0;
  final subscriptions = <StreamSubscription<dynamic>>[];
  final transitions = <Timer>[];
  late WebController controller;
  bool neutral() => command.every((v) => v == 0);
  controller = WebController(
    token: token,
    assetsPath: 'thunder/web',
    status: () {
      final p = profiles[slot]!;
      return {
        'ready': true,
        'preview': true,
        'cms': cms,
        'motor_enabled': enabled,
        'can_enable': true,
        'can_switch':
            enabled &&
            neutral() &&
            (cms == 'GROUNDED' || (cms == 'STANDING' && l1)),
        'can_zero': !enabled && cms == 'GROUNDED',
        'can_open_zero': !enabled && cms == 'GROUNDED',
        'zero_block_reason': enabled ? '请先断使能' : null,
        'zero_phase': !enabled && cms == 'GROUNDED' ? 'ready' : 'waiting',
        'block_reason': null,
        'model_slot': slot,
        'model_profile': slots[slot],
        'slots': slots,
        'limits': {
          'vx': p['commandVxMax'],
          'vy': p['commandVyMax'],
          'yaw': p['commandYawMax'],
        },
        'minimums': {
          'vx': p['forwardMinCommand'],
          'vy': p['lateralMinCommand'],
          'yaw': p['yawMinCommand'],
        },
        'deadzone': 0.1,
        'command': command,
        'preview_zero_count': zeroCount,
        'preview_hard_stop_count': hardStopCount,
        'preview_input_count': inputCount,
        'motors': [
          for (var i = 0; i < 16; i++)
            {
              'id': i,
              'leg': ['FR', 'FL', 'RR', 'RL'][i < 12 ? i ~/ 3 : i - 12],
              'joint': i < 12 ? ['Hip', 'Thigh', 'Calf'][i % 3] : 'Foot',
              'online': true,
              'status': enabled ? 2 : 0,
              'position': positions[i],
              'errors': <int>[],
            },
        ],
      };
    },
    selectSlot: (next) async {
      slot = next;
    },
    zeroAll: () async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      zeroCount++;
      positions = List<double>.filled(16, 0);
      return {'verified': 16, 'power_cycle_verified': false, 'preview': true};
    },
  );
  subscriptions.add(
    controller.enabled.listen((value) {
      enabled = value;
      if (!value) command = [0, 0, 0];
    }),
  );
  subscriptions.add(
    controller.direction.listen((raw) {
      inputCount++;
      final p = profiles[slot]!;
      command = [
        shapeSignedCommand(
          raw.x,
          deadzone: 0.1,
          minCommand: (p['forwardMinCommand'] as num).toDouble(),
          maxCommand: (p['commandVxMax'] as num).toDouble(),
        ),
        shapeSignedCommand(
          raw.y,
          deadzone: 0.1,
          minCommand: (p['lateralMinCommand'] as num).toDouble(),
          maxCommand: (p['commandVyMax'] as num).toDouble(),
        ),
        shapeSignedCommand(
          raw.z,
          deadzone: 0.1,
          minCommand: (p['yawMinCommand'] as num).toDouble(),
          maxCommand: (p['commandYawMax'] as num).toDouble(),
        ),
      ];
      if (!neutral()) {
        cms = 'WALKING';
        l1 = false;
      }
    }),
  );
  subscriptions.add(
    controller.hardStop.listen((_) {
      command = [0, 0, 0];
      hardStopCount++;
      l1 = false;
    }),
  );
  subscriptions.add(
    controller.standup.listen((_) {
      cms = 'TRANSITIONING';
      transitions.add(
        Timer(const Duration(milliseconds: 150), () {
          cms = 'STANDING';
          l1 = true;
          positions = (profiles[slot]!['standingPose'] as List)
              .map((v) => (v as num).toDouble())
              .toList();
        }),
      );
    }),
  );
  subscriptions.add(
    controller.sitdown.listen((_) {
      command = [0, 0, 0];
      cms = 'TRANSITIONING';
      transitions.add(
        Timer(const Duration(milliseconds: 150), () {
          cms = 'GROUNDED';
          l1 = false;
          positions = List<double>.filled(16, 0);
        }),
      );
    }),
  );
  await controller.start(host: host, port: port);
  stdout.writeln('PREVIEW ONLY: NO ROBOT CONNECTION, NO MOTOR COMMANDS');
  stdout.writeln(
    'http://${host == '0.0.0.0' ? '127.0.0.1' : host}:${controller.boundPort}',
  );
  stdout.writeln('Preview token: $token');
  Future<void> shutdown() async {
    for (final timer in transitions) {
      timer.cancel();
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await controller.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }
}
