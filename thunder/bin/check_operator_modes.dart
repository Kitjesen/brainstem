import 'dart:convert';
import 'dart:io';

import 'package:thunder/src/app/config.dart';
import 'package:thunder/src/app/operator_mode_slots.dart';
import 'package:thunder/src/app/robot_profile.dart';

/// Configuration-only preflight. Does not open devices or load ONNX sessions.
Future<void> main(List<String> args) async {
  try {
    if (args.length > 2) {
      throw const FormatException(
        'Usage: check_operator_modes.dart [slots.json] [profileDir]',
      );
    }
    final config = ThunderConfig();
    final path = args.isNotEmpty ? args[0] : config.operatorModesPath;
    final directory = args.length == 2 ? args[1] : config.profileDir;
    final profiles = await loadProfiles(directory);
    final slots = await OperatorModeSlots.load(path);
    slots.validateProfiles(profiles);
    stdout.writeln(
      jsonEncode({
        'config': path,
        'flat': slots.flat,
        'stairs': slots.stairs,
        'defaultProfile': slots.defaultProfile,
        'configuration_valid': true,
        'model_contract_verified': false,
        'devices_opened': false,
      }),
    );
  } catch (error) {
    stderr.writeln('Operator modes invalid: $error');
    exitCode = 1;
  }
}
