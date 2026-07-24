import 'dart:io';

import 'package:test/test.dart';

const _expectedConstructorMapping = {
  'fr': 'usbbus4',
  'fl': 'usbbus3',
  'rr': 'usbbus2',
  'rl': 'usbbus1',
};

const _expectedNamedMapping = {
  'FR': 'usbbus4',
  'FL': 'usbbus3',
  'RR': 'usbbus2',
  'RL': 'usbbus1',
};

const _realJointEntryPoints = [
  'han_dog/bin/han_dog.dart',
  'han_dog/bin/joint_angle_monitor.dart',
  'han_dog/bin/read_joints.dart',
  'han_dog/bin/read_voltage.dart',
  'han_dog/bin/set_zero.dart',
  'han_dog/example/demo_basic_grpc.dart',
  'han_dog/example/demo_full_controller.dart',
];

void main() {
  test('real-hardware entry points use the field-verified PCAN leg mapping', () {
    for (final path in _realJointEntryPoints) {
      final source = File(path).readAsStringSync();
      for (final entry in _expectedConstructorMapping.entries) {
        expect(
          source,
          contains('${entry.key}: .${entry.value},'),
          reason: '$path must map ${entry.key.toUpperCase()} to ${entry.value}',
        );
      }
    }
  });

  test('leg-mapping diagnostics use the field-verified PCAN channels', () {
    for (final path in [
      'han_dog/bin/ping.dart',
      'han_dog/bin/verify_leg_mapping_passive.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final entry in _expectedNamedMapping.entries) {
        expect(
          source,
          contains("'${entry.key}': PcanChannel.${entry.value},"),
          reason: '$path must map ${entry.key} to ${entry.value}',
        );
      }
    }
  });

  test('raw PCAN labels identify the verified physical legs', () {
    final source = File('han_dog/bin/ping_raw.dart').readAsStringSync();

    expect(source, contains('can0 (usbbus1/RL)'));
    expect(source, contains('can1 (usbbus2/RR)'));
    expect(source, contains('can2 (usbbus3/FL)'));
    expect(source, contains('can3 (usbbus4/FR)'));
  });
}
