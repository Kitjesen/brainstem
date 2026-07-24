/// Passive PCAN leg-mapping verifier for HAN DOG.
///
/// Final interaction flow:
/// 1. The tool asks you to prepare one physical leg.
/// 2. After you press Enter, it first waits until all 16 joints are stable.
/// 3. Only after stability is confirmed does it arm movement detection.
/// 4. As soon as clear movement is detected, it keeps sampling briefly.
/// 5. It records the most-changed logical leg/joint, then waits for Enter.
///
/// Run:
///   dart run han_dog/bin/verify_leg_mapping_passive.dart
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

const _legConfig = <String, PcanChannel>{
  'FR': PcanChannel.usbbus4,
  'FL': PcanChannel.usbbus3,
  'RR': PcanChannel.usbbus2,
  'RL': PcanChannel.usbbus1,
};

const _jointNames = ['Hip', 'Thigh', 'Calf', 'Foot'];
const _motorsPerLeg = 4;

const _reportWarmup = Duration(seconds: 1);
const _pollStep = Duration(milliseconds: 20);
const _idleReminder = Duration(seconds: 3);
const _confirmWindow = Duration(milliseconds: 1200);
const _settleAfterDisable = Duration(milliseconds: 600);
const _stableWindow = Duration(milliseconds: 800);

const _movementThresholdRad = 0.08;
const _stableThresholdRad = 0.015;

void main() async {
  stdout.writeln('');
  stdout.writeln('╔══════════════════════════════════════════════╗');
  stdout.writeln('║     HAN DOG PCAN LEG MAPPING VERIFIER       ║');
  stdout.writeln('╚══════════════════════════════════════════════╝');
  stdout.writeln('');
  stdout.writeln('This tool only reads angle reports. It does not command motion.');
  stdout.writeln('Recommended: keep all four legs off the ground.');
  stdout.writeln('');

  if (!_confirm('Continue? [y/N]: ')) {
    stdout.writeln('Cancelled.');
    exit(1);
  }

  final found = <String, BigInt>{};
  final latestReports = <String, RSStateReport>{};
  final pcans = <String, PcanController<RSEvent, RSState>>{};
  final subscriptions = <StreamSubscription<RSState>>[];
  final detectedByPhysical = <String, String>{};

  try {
    stdout.writeln('');
    stdout.writeln('[1/4] Opening PCAN channels...');
    for (final entry in _legConfig.entries) {
      final pcan = PcanController<RSEvent, RSState>(entry.value);
      if (!pcan.open()) {
        stdout.writeln('  ${entry.key} (${entry.value.name}) x open failed');
        continue;
      }
      pcans[entry.key] = pcan;
      stdout.writeln('  ${entry.key} (${entry.value.name}) ok');
      subscriptions.add(pcan.state.listen((state) {
        if (state is RSStateDeviceId) {
          found['${entry.key}-${state.canId}'] = state.mcuId;
        } else if (state is RSStateReport) {
          latestReports['${entry.key}-${state.canId}'] = state;
        }
      }));
    }

    if (pcans.length != _legConfig.length) {
      stdout.writeln('');
      stdout.writeln('[ERROR] Not all PCAN channels opened.');
      exit(1);
    }

    stdout.writeln('');
    stdout.writeln('[2/4] Checking motors and enabling reports...');
    for (final entry in pcans.entries) {
      for (int canId = 1; canId <= _motorsPerLeg; canId++) {
        entry.value.add(RSEvent.getDeviceId(canId));
        entry.value.add(RSEvent.setReporting(canId, enable: true));
        entry.value.add(RSEvent.disable(canId));
      }
    }
    await Future<void>.delayed(_reportWarmup);

    final missing = <String>[];
    for (final leg in _legConfig.keys) {
      for (int canId = 1; canId <= _motorsPerLeg; canId++) {
        final key = '$leg-$canId';
        if (!found.containsKey(key) || !latestReports.containsKey(key)) {
          missing.add('$leg-${_jointNames[canId - 1]}');
        }
      }
    }

    if (missing.isNotEmpty) {
      stdout.writeln('  Missing responses from these joints:');
      for (final item in missing) {
        stdout.writeln('  - $item');
      }
      exit(1);
    }

    stdout.writeln('  ok all 16 joints are online and reporting');
    stdout.writeln('  ok all motors have been disabled for manual movement');

    stdout.writeln('');
    stdout.writeln('[3/4] Starting four manual verification rounds');
    stdout.writeln('');

    for (final physicalLeg in ['FR', 'FL', 'RR', 'RL']) {
      await Future<void>.delayed(_settleAfterDisable);

      stdout.writeln('Round for physical leg: $physicalLeg');
      stdout.writeln('Do not touch the robot until the script says LISTENING NOW.');
      stdout.writeln('Then move only this physical leg.');
      _pause('Press Enter to begin this round...');

      stdout.writeln('');
      stdout.writeln('>>> HOLD STILL');
      stdout.writeln('>>> Waiting for all joints to become stable...');
      final baseline = await _waitForStableBaseline(latestReports);

      stdout.writeln('>>> LISTENING NOW');
      stdout.writeln('>>> Move physical $physicalLeg now.');
      final result = await _sampleMovement(latestReports, baseline);
      stdout.writeln('');

      if (result == null) {
        stdout.writeln('  x No clear movement detected. Please retry this round.');
        stdout.writeln('');
        _pause('Press Enter to continue...');
        stdout.writeln('');
        continue;
      }

      final logicalLeg = result.leg;
      final channel = _legConfig[logicalLeg]!;
      detectedByPhysical[physicalLeg] = logicalLeg;
      stdout.writeln('  RECORDED');
      stdout.writeln(
        '  physical $physicalLeg -> logical $logicalLeg (${channel.name})',
      );
      stdout.writeln(
        '  changed joint: $logicalLeg ${_jointNames[result.canId - 1]} '
        '${_formatDegree(result.maxJointDeltaRad)} deg',
      );
      stdout.writeln(
        '  per-leg peak: '
        'FR=${_formatDegree(result.legDeltaRad['FR']!)} deg, '
        'FL=${_formatDegree(result.legDeltaRad['FL']!)} deg, '
        'RR=${_formatDegree(result.legDeltaRad['RR']!)} deg, '
        'RL=${_formatDegree(result.legDeltaRad['RL']!)} deg',
      );
      stdout.writeln('');
      _pause('Press Enter for the next leg...');
      stdout.writeln('');
    }

    stdout.writeln('[4/4] Summary');
    stdout.writeln('');
    stdout.writeln(
      '  ${'Physical'.padRight(10)}${'Logical'.padRight(18)}${'PCAN'.padRight(12)}Result',
    );
    stdout.writeln('  ${'─' * 58}');
    for (final physicalLeg in ['FR', 'FL', 'RR', 'RL']) {
      final logicalLeg = detectedByPhysical[physicalLeg];
      final pcanText = logicalLeg == null ? '-' : _legConfig[logicalLeg]!.name;
      final conclusion = logicalLeg == null
          ? 'unknown'
          : (logicalLeg == physicalLeg ? 'match' : 'mismatch');
      stdout.writeln(
        '  ${physicalLeg.padRight(10)}'
        '${(logicalLeg ?? '-').padRight(18)}'
        '${pcanText.padRight(12)}'
        '$conclusion',
      );
    }
    stdout.writeln('  ${'─' * 58}');
    stdout.writeln('');
    stdout.writeln('To fix mapping, use: physical leg -> detected logical leg -> current PCAN.');
    stdout.writeln('');
  } finally {
    for (final entry in pcans.entries) {
      for (int canId = 1; canId <= _motorsPerLeg; canId++) {
        entry.value.add(RSEvent.setReporting(canId, enable: false));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    for (final pcan in pcans.values) {
      pcan.dispose();
    }
  }
}

Future<Map<String, List<double>>> _waitForStableBaseline(
  Map<String, RSStateReport> reports,
) async {
  DateTime stableSince = DateTime.now();
  var reference = _snapshotLegs(reports);
  var lastReminderAt = DateTime.now();

  while (true) {
    await Future<void>.delayed(_pollStep);
    final current = _snapshotLegs(reports);
    final maxDelta = _maxDeltaBetween(reference, current);

    if (maxDelta <= _stableThresholdRad) {
      if (DateTime.now().difference(stableSince) >= _stableWindow) {
        return current;
      }
    } else {
      reference = current;
      stableSince = DateTime.now();
    }

    final now = DateTime.now();
    if (now.difference(lastReminderAt) >= _idleReminder) {
      stdout.writeln(
        '...still waiting for stable joints '
        '(max drift ${_formatDegree(maxDelta)} deg)',
      );
      lastReminderAt = now;
    }
  }
}

Map<String, List<double>> _snapshotLegs(Map<String, RSStateReport> reports) {
  final snapshot = <String, List<double>>{};
  for (final leg in _legConfig.keys) {
    snapshot[leg] = [
      for (int canId = 1; canId <= _motorsPerLeg; canId++)
        reports['$leg-$canId']!.position,
    ];
  }
  return snapshot;
}

double _maxDeltaBetween(
  Map<String, List<double>> a,
  Map<String, List<double>> b,
) {
  var maxDelta = 0.0;
  for (final leg in _legConfig.keys) {
    final va = a[leg]!;
    final vb = b[leg]!;
    for (int i = 0; i < _motorsPerLeg; i++) {
      maxDelta = math.max(maxDelta, (vb[i] - va[i]).abs());
    }
  }
  return maxDelta;
}

Future<_MovementResult?> _sampleMovement(
  Map<String, RSStateReport> reports,
  Map<String, List<double>> baseline,
) async {
  final maxPerLeg = <String, double>{
    for (final leg in _legConfig.keys) leg: 0,
  };
  final maxPerJoint = <String, double>{
    for (final leg in _legConfig.keys)
      for (int canId = 1; canId <= _motorsPerLeg; canId++) '$leg-$canId': 0,
  };

  DateTime? confirmUntil;
  var lastReminderAt = DateTime.now();

  while (true) {
    String currentTopLeg = '';
    double currentTopDelta = 0;

    for (final leg in _legConfig.keys) {
      final base = baseline[leg]!;
      for (int canId = 1; canId <= _motorsPerLeg; canId++) {
        final current = reports['$leg-$canId']?.position;
        if (current == null) continue;
        final delta = (current - base[canId - 1]).abs();
        final jointKey = '$leg-$canId';
        maxPerLeg[leg] = math.max(maxPerLeg[leg]!, delta);
        maxPerJoint[jointKey] = math.max(maxPerJoint[jointKey]!, delta);
        if (delta > currentTopDelta) {
          currentTopDelta = delta;
          currentTopLeg = leg;
        }
      }
    }

    if (confirmUntil == null &&
        currentTopDelta >= _movementThresholdRad &&
        currentTopLeg.isNotEmpty) {
      confirmUntil = DateTime.now().add(_confirmWindow);
      stdout.writeln('...movement detected, sampling a bit more to confirm');
    }

    if (confirmUntil != null && DateTime.now().isAfter(confirmUntil)) {
      break;
    }

    final now = DateTime.now();
    if (confirmUntil == null && now.difference(lastReminderAt) >= _idleReminder) {
      stdout.writeln('...waiting for a clear angle change');
      lastReminderAt = now;
    }
    await Future<void>.delayed(_pollStep);
  }

  final topJoint = maxPerJoint.entries.reduce(
    (a, b) => a.value >= b.value ? a : b,
  );
  if (topJoint.value < _movementThresholdRad) {
    return null;
  }

  final parts = topJoint.key.split('-');
  return _MovementResult(
    leg: parts[0],
    canId: int.parse(parts[1]),
    maxJointDeltaRad: topJoint.value,
    legDeltaRad: maxPerLeg,
  );
}

bool _confirm(String prompt) {
  stdout.write(prompt);
  final input = stdin.readLineSync()?.trim().toLowerCase();
  return input == 'y' || input == 'yes';
}

void _pause(String prompt) {
  stdout.write(prompt);
  stdin.readLineSync();
}

String _formatDegree(double rad) {
  return (rad * 180 / math.pi).toStringAsFixed(1);
}

class _MovementResult {
  final String leg;
  final int canId;
  final double maxJointDeltaRad;
  final Map<String, double> legDeltaRad;

  const _MovementResult({
    required this.leg,
    required this.canId,
    required this.maxJointDeltaRad,
    required this.legDeltaRad,
  });
}

