/// Real-time 16-joint angle monitor for HAN DOG.
///
/// Run:
///   dart run han_dog/bin/joint_angle_monitor.dart
library;

import 'dart:async';
import 'dart:io';

import 'package:han_dog/han_dog.dart';

const _refreshPeriod = Duration(milliseconds: 200);

void main() async {
  final joint = RealJoint(
    fr: .usbbus1,
    fl: .usbbus2,
    rr: .usbbus3,
    rl: .usbbus4,
  );

  if (!joint.open()) {
    stderr.writeln('Failed to open all PCAN channels.');
    exit(1);
  }

  joint.setReporting(true);
  await Future<void>.delayed(const Duration(seconds: 1));

  ProcessSignal.sigint.watch().listen((_) async {
    await _shutdown(joint);
    exit(0);
  });

  stdout.writeln('Monitoring 16 joint angles. Press Ctrl+C to exit.');

  final timer = Timer.periodic(_refreshPeriod, (_) {
    final pos = joint.position;
    final hz = joint.frequencyWatches.map((e) => e.value).toList();

    stdout.write('\x1B[2J\x1B[H');
    stdout.writeln('HAN DOG joint angle monitor');
    stdout.writeln('');
    stdout.writeln('Leg   Joint   Angle(rad)  Hz   State');
    stdout.writeln('------------------------------------');

    _printLeg(
      'FR',
      [pos.frHip, pos.frThigh, pos.frCalf, pos.frFoot],
      hz.sublist(0, 4),
    );
    _printLeg(
      'FL',
      [pos.flHip, pos.flThigh, pos.flCalf, pos.flFoot],
      hz.sublist(4, 8),
    );
    _printLeg(
      'RR',
      [pos.rrHip, pos.rrThigh, pos.rrCalf, pos.rrFoot],
      hz.sublist(8, 12),
    );
    _printLeg(
      'RL',
      [pos.rlHip, pos.rlThigh, pos.rlCalf, pos.rlFoot],
      hz.sublist(12, 16),
    );

    stdout.writeln('');
    stdout.writeln('Press Ctrl+C to stop.');
  });

  await Completer<void>().future;
  timer.cancel();
}

void _printLeg(String leg, List<double> angles, List<int> hz) {
  const joints = ['Hip', 'Thigh', 'Calf', 'Foot'];
  for (int i = 0; i < joints.length; i++) {
    final online = hz[i] > 0 ? 'online' : 'offline';
    stdout.writeln(
      '${leg.padRight(5)}'
      '${joints[i].padRight(8)}'
      '${angles[i].toStringAsFixed(4).padRight(12)}'
      '${hz[i].toString().padRight(5)}'
      '$online',
    );
  }
}

Future<void> _shutdown(RealJoint joint) async {
  stdout.writeln('\nStopping monitor...');
  joint.setReporting(false);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  joint.dispose();
}

