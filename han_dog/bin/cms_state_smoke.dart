library;

import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart' hide Duration;

const _defaultHost = '127.0.0.1';
const _defaultPort = 13145;
const _defaultTransitionTicks = 220;
const _defaultWalkTicks = 12;

Future<void> main(List<String> args) async {
  final config = SmokeConfig.parse(args);
  if (config.showHelp) {
    _printHelp();
    return;
  }

  final channel = ClientChannel(
    config.host,
    port: config.port,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  final client = CmsClient(channel);

  try {
    await CmsStateSmoke(client: client, config: config).run();
  } finally {
    await channel.shutdown();
  }
}

class SmokeConfig {
  SmokeConfig({
    required this.host,
    required this.port,
    required this.maxTransitionTicks,
    required this.maxWalkTicks,
    required this.walkX,
    required this.walkY,
    required this.walkZ,
    required this.showHelp,
  });

  final String host;
  final int port;
  final int maxTransitionTicks;
  final int maxWalkTicks;
  final double walkX;
  final double walkY;
  final double walkZ;
  final bool showHelp;

  factory SmokeConfig.parse(List<String> args) {
    var host = _defaultHost;
    var port = _defaultPort;
    var maxTransitionTicks = _defaultTransitionTicks;
    var maxWalkTicks = _defaultWalkTicks;
    var walkX = 0.2;
    var walkY = 0.0;
    var walkZ = 0.0;
    var showHelp = false;

    String readValue(String current, int index) {
      final parts = current.split('=');
      if (parts.length == 2) {
        return parts[1];
      }
      if (index + 1 >= args.length) {
        throw FormatException('Missing value for $current');
      }
      return args[index + 1];
    }

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '-h':
        case '--help':
          showHelp = true;
          continue;
      }

      if (arg.startsWith('--host')) {
        host = readValue(arg, i);
        if (!arg.contains('=')) i++;
        continue;
      }
      if (arg.startsWith('--port')) {
        port = int.parse(readValue(arg, i));
        if (!arg.contains('=')) i++;
        continue;
      }
      if (arg.startsWith('--max-transition-ticks')) {
        maxTransitionTicks = int.parse(readValue(arg, i));
        if (!arg.contains('=')) i++;
        continue;
      }
      if (arg.startsWith('--max-walk-ticks')) {
        maxWalkTicks = int.parse(readValue(arg, i));
        if (!arg.contains('=')) i++;
        continue;
      }
      if (arg.startsWith('--walk-x')) {
        walkX = double.parse(readValue(arg, i));
        if (!arg.contains('=')) i++;
        continue;
      }
      if (arg.startsWith('--walk-y')) {
        walkY = double.parse(readValue(arg, i));
        if (!arg.contains('=')) i++;
        continue;
      }
      if (arg.startsWith('--walk-z')) {
        walkZ = double.parse(readValue(arg, i));
        if (!arg.contains('=')) i++;
        continue;
      }

      throw FormatException('Unknown argument: $arg');
    }

    return SmokeConfig(
      host: host,
      port: port,
      maxTransitionTicks: maxTransitionTicks,
      maxWalkTicks: maxWalkTicks,
      walkX: walkX,
      walkY: walkY,
      walkZ: walkZ,
      showHelp: showHelp,
    );
  }
}

class CmsStateSmoke {
  CmsStateSmoke({required this.client, required this.config});

  final CmsClient client;
  final SmokeConfig config;

  Future<void> run() async {
    final observed = <String>[];
    final subscription = client.listenCmsState(Empty()).listen((state) {
      final desc = describe(state);
      if (observed.isEmpty || observed.last != desc) {
        observed.add(desc);
        stdout.writeln('stream => $desc');
      }
    });

    try {
      final start = await client.getStartTime(Empty());
      stdout.writeln('start_time_utc => ${_timestampToUtcString(start)}');
      stdout.writeln('target => ${config.host}:${config.port}');

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final initial = await client.getCmsState(Empty());
      stdout.writeln('initial => ${describe(initial)}');
      _require(
        initial.kind == CmsStateKind.CMS_STATE_KIND_GROUNDED,
        'Expected initial GROUNDED, got ${describe(initial)}',
      );

      await _expectGroundedWalkRejected();

      await client.standUp(Empty());
      final afterStandUp = await client.getCmsState(Empty());
      stdout.writeln('after standUp => ${describe(afterStandUp)}');
      _require(
        afterStandUp.kind == CmsStateKind.CMS_STATE_KIND_TRANSITIONING &&
            afterStandUp.transition ==
                CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP,
        'Expected TRANSITIONING/STAND_UP, got ${describe(afterStandUp)}',
      );
      await _tickUntil(
        label: 'STANDING',
        predicate: (state) =>
            state.kind == CmsStateKind.CMS_STATE_KIND_STANDING,
        maxTicks: config.maxTransitionTicks,
      );

      await client.walk(
        Vector3(x: config.walkX, y: config.walkY, z: config.walkZ),
      );
      await _tickUntil(
        label: 'WALKING',
        predicate: (state) => state.kind == CmsStateKind.CMS_STATE_KIND_WALKING,
        maxTicks: config.maxWalkTicks,
      );

      await client.standUp(Empty());
      final afterWalkStop = await client.getCmsState(Empty());
      stdout.writeln(
        'after standUp-from-walking => ${describe(afterWalkStop)}',
      );
      _require(
        afterWalkStop.kind == CmsStateKind.CMS_STATE_KIND_TRANSITIONING &&
            afterWalkStop.transition ==
                CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP,
        'Expected TRANSITIONING/STAND_UP after stopping walk, got '
        '${describe(afterWalkStop)}',
      );
      await _tickUntil(
        label: 'STANDING (after walk)',
        predicate: (state) =>
            state.kind == CmsStateKind.CMS_STATE_KIND_STANDING,
        maxTicks: config.maxTransitionTicks,
      );

      await client.sitDown(Empty());
      final afterSitDown = await client.getCmsState(Empty());
      stdout.writeln('after sitDown => ${describe(afterSitDown)}');
      _require(
        afterSitDown.kind == CmsStateKind.CMS_STATE_KIND_TRANSITIONING &&
            afterSitDown.transition ==
                CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN,
        'Expected TRANSITIONING/SIT_DOWN, got ${describe(afterSitDown)}',
      );
      await _tickUntil(
        label: 'GROUNDED (after sitDown)',
        predicate: (state) =>
            state.kind == CmsStateKind.CMS_STATE_KIND_GROUNDED,
        maxTicks: config.maxTransitionTicks,
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      stdout.writeln('observed => ${observed.join(' -> ')}');

      for (final requiredState in const [
        'GROUNDED',
        'TRANSITIONING/STAND_UP',
        'STANDING',
        'WALKING',
        'TRANSITIONING/SIT_DOWN',
      ]) {
        _require(
          observed.any((state) => state.contains(requiredState)),
          'State stream missed $requiredState; observed=$observed',
        );
      }

      stdout.writeln('CMS smoke OK');
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _expectGroundedWalkRejected() async {
    try {
      await client.walk(
        Vector3(x: config.walkX, y: config.walkY, z: config.walkZ),
      );
      throw StateError('Walk unexpectedly succeeded while grounded');
    } on GrpcError catch (error) {
      stdout.writeln(
        'walk while grounded => code=${error.codeName} message=${error.message}',
      );
      _require(
        error.code == StatusCode.failedPrecondition,
        'Expected FAILED_PRECONDITION for grounded walk, got '
        '${error.codeName}: ${error.message}',
      );
    }
  }

  Future<CmsState> _tickUntil({
    required String label,
    required bool Function(CmsState state) predicate,
    required int maxTicks,
  }) async {
    String? last;
    for (var i = 1; i <= maxTicks; i++) {
      try {
        await client.tick(Empty());
      } on GrpcError catch (error) {
        if (error.code == StatusCode.failedPrecondition &&
            error.message == 'Tick is not available in hardware mode') {
          throw StateError(
            'This smoke script requires server.dart or another simulation '
            'service that supports Tick.',
          );
        }
        rethrow;
      }

      final state = await client.getCmsState(Empty());
      final desc = describe(state);
      if (desc != last || i % 25 == 0) {
        stdout.writeln('tick $i => $desc');
      }
      if (predicate(state)) {
        stdout.writeln('reached $label after $i ticks');
        return state;
      }
      last = desc;
    }
    throw StateError('Did not reach $label within $maxTicks ticks; last=$last');
  }

  static String describe(CmsState state) {
    final kind = state.kind.name.replaceFirst('CMS_STATE_KIND_', '');
    if (state.kind != CmsStateKind.CMS_STATE_KIND_TRANSITIONING) {
      return kind;
    }
    final transition = state.transition.name.replaceFirst(
      'CMS_TRANSITION_KIND_',
      '',
    );
    final gesture = state.gestureName.isEmpty ? '' : '(${state.gestureName})';
    return '$kind/$transition$gesture';
  }

  static String _timestampToUtcString(Timestamp ts) {
    final millis = ts.seconds.toInt() * 1000 + ts.nanos ~/ 1000000;
    return DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).toIso8601String();
  }

  static void _require(bool condition, String message) {
    if (!condition) {
      throw StateError(message);
    }
  }
}

void _printHelp() {
  stdout.writeln('CMS authoritative state smoke');
  stdout.writeln('');
  stdout.writeln('Usage:');
  stdout.writeln('  dart run han_dog/bin/cms_state_smoke.dart [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --host <host>                  default: $_defaultHost');
  stdout.writeln('  --port <port>                  default: $_defaultPort');
  stdout.writeln(
    '  --max-transition-ticks <n>     default: $_defaultTransitionTicks',
  );
  stdout.writeln(
    '  --max-walk-ticks <n>           default: $_defaultWalkTicks',
  );
  stdout.writeln('  --walk-x <value>               default: 0.2');
  stdout.writeln('  --walk-y <value>               default: 0.0');
  stdout.writeln('  --walk-z <value>               default: 0.0');
  stdout.writeln('  -h, --help');
  stdout.writeln('');
  stdout.writeln(
    'This script is intended for medulla/server.dart or other simulation '
    'targets that support Tick.',
  );
}
