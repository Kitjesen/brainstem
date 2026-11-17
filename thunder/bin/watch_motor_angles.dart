library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

const _defaultPeriod = Duration(milliseconds: 200);
const _ids = [1, 2, 3, 4];
const _jointNames = {1: 'hip', 2: 'thigh', 3: 'calf', 4: 'foot'};

const _legs = <_LegConfig>[
  _LegConfig('RL', PcanChannel.usbbus1, 'port1 1-2.1.1 can0'),
  _LegConfig('RR', PcanChannel.usbbus2, 'port2 1-2.1.2 can1'),
  _LegConfig('FL', PcanChannel.usbbus3, 'port3 1-2.1.3 can2'),
  _LegConfig('FR', PcanChannel.usbbus4, 'port4 1-2.1.4 can3'),
];

void main(List<String> args) async {
  final period = Duration(
    milliseconds: _intArg(args, '--period-ms', _defaultPeriod.inMilliseconds),
  );
  final durationSec = _intArg(args, '--duration-sec', 0);
  final noClear = _boolArg(args, '--no-clear', false);

  final monitors = <_LegMonitor>[];
  var allOpened = true;

  stdout.writeln('HAN DOG read-only motor angle watcher');
  stdout.writeln('Mapping: port1=RL, port2=RR, port3=FL, port4=FR');
  stdout.writeln('Only sends Robstride get(mechPos). No enable/control/save.');
  stdout.writeln('');

  for (final leg in _legs) {
    final controller = PcanController<RSEvent, RSState>(leg.channel);
    final opened = controller.open();
    stdout.writeln(
      '${leg.name.padRight(2)} ${leg.note}: '
      '${opened ? 'opened' : 'open failed'}',
    );
    if (!opened) {
      allOpened = false;
      controller.dispose();
      continue;
    }

    final monitor = _LegMonitor(leg, controller);
    monitor.start();
    monitors.add(monitor);
  }

  if (monitors.isEmpty || !allOpened) {
    stderr.writeln('Not all CAN channels opened; exiting.');
    for (final monitor in monitors) {
      monitor.dispose();
    }
    exitCode = 2;
    return;
  }

  ProcessSignal.sigint.watch().listen((_) {
    _shutdown(monitors);
    exit(0);
  });

  final queryTimer = Timer.periodic(period, (_) {
    for (final monitor in monitors) {
      monitor.query();
    }
  });

  Timer? stopTimer;
  if (durationSec > 0) {
    stopTimer = Timer(Duration(seconds: durationSec), () {
      queryTimer.cancel();
      _render(monitors, noClear: noClear);
      _shutdown(monitors);
      exit(0);
    });
  }

  final renderTimer = Timer.periodic(period, (_) {
    _render(monitors, noClear: noClear);
  });

  // Prime the first query immediately.
  for (final monitor in monitors) {
    monitor.query();
  }

  await Completer<void>().future;
  queryTimer.cancel();
  renderTimer.cancel();
  stopTimer?.cancel();
}

void _render(List<_LegMonitor> monitors, {required bool noClear}) {
  if (!noClear) {
    stdout.write('\x1B[2J\x1B[H');
  }

  stdout.writeln('HAN DOG read-only motor angle watcher');
  stdout.writeln('Move motors by hand. Watch delta and dir. Ctrl+C to stop.');
  stdout.writeln('');
  stdout.writeln(
    'Leg Id Joint  Angle(rad) Angle(deg)  Base(rad)  Delta(rad) '
    'Delta(deg) Dir  Age(ms)',
  );
  stdout.writeln(
    '--------------------------------------------------------------------------',
  );

  for (final monitor in monitors) {
    for (final id in _ids) {
      final sample = monitor.samples[id];
      final joint = _jointNames[id]!;
      if (sample == null) {
        stdout.writeln(
          '${monitor.leg.name.padRight(3)} '
          '${id.toString().padLeft(2)} '
          '${joint.padRight(6)} '
          '${'--'.padLeft(10)} ${'--'.padLeft(10)} '
          '${'--'.padLeft(10)} ${'--'.padLeft(10)} '
          '${'--'.padLeft(10)} ${'--'.padLeft(3)} '
          '${'offline'.padLeft(7)}',
        );
        continue;
      }

      final delta = sample.value - sample.base;
      final direction = delta.abs() < 0.003
          ? '0'
          : delta > 0
          ? '+'
          : '-';
      final ageMs = DateTime.now().difference(sample.updatedAt).inMilliseconds;
      stdout.writeln(
        '${monitor.leg.name.padRight(3)} '
        '${id.toString().padLeft(2)} '
        '${joint.padRight(6)} '
        '${sample.value.toStringAsFixed(4).padLeft(10)} '
        '${_deg(sample.value).toStringAsFixed(1).padLeft(10)} '
        '${sample.base.toStringAsFixed(4).padLeft(10)} '
        '${delta.toStringAsFixed(4).padLeft(10)} '
        '${_deg(delta).toStringAsFixed(1).padLeft(10)} '
        '${direction.padLeft(3)} '
        '${ageMs.toString().padLeft(7)}',
      );
    }
  }

  stdout.writeln('');
  stdout.writeln('USB mapping: port1=RL, port2=RR, port3=FL, port4=FR');
}

void _shutdown(List<_LegMonitor> monitors) {
  stdout.writeln('\nStopping watcher...');
  for (final monitor in monitors) {
    monitor.dispose();
  }
}

double _deg(double rad) => rad * 180.0 / math.pi;

int _intArg(List<String> args, String name, int fallback) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return int.tryParse(arg.substring(prefix.length)) ?? fallback;
    }
  }
  return fallback;
}

bool _boolArg(List<String> args, String name, bool fallback) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg == name) return true;
    if (arg.startsWith(prefix)) {
      final value = arg.substring(prefix.length).toLowerCase();
      return switch (value) {
        '1' || 'true' || 'yes' || 'on' => true,
        '0' || 'false' || 'no' || 'off' => false,
        _ => fallback,
      };
    }
  }
  return fallback;
}

class _LegConfig {
  final String name;
  final PcanChannel channel;
  final String note;

  const _LegConfig(this.name, this.channel, this.note);
}

class _LegMonitor {
  final _LegConfig leg;
  final PcanController<RSEvent, RSState> controller;
  final samples = <int, _AngleSample>{};

  StreamSubscription<RSState>? _subscription;

  _LegMonitor(this.leg, this.controller);

  void start() {
    _subscription = controller.state.listen((state) {
      if (state is RSStateGetter) {
        final getter = state.getter;
        if (getter is RSGetterMechPos && _ids.contains(state.canId)) {
          _update(state.canId, getter.value);
        }
      } else if (state is RSStateReport && _ids.contains(state.canId)) {
        _update(state.canId, state.position);
      }
    });
  }

  void query() {
    for (final id in _ids) {
      controller.add(RSEvent.get(id, key: RSKey.mechPos));
    }
  }

  void _update(int id, double value) {
    final existing = samples[id];
    if (existing == null) {
      samples[id] = _AngleSample(value, value, DateTime.now());
    } else {
      existing
        ..value = value
        ..updatedAt = DateTime.now();
    }
  }

  void dispose() {
    _subscription?.cancel();
    controller.dispose();
  }
}

class _AngleSample {
  final double base;
  double value;
  DateTime updatedAt;

  _AngleSample(this.base, this.value, this.updatedAt);
}
