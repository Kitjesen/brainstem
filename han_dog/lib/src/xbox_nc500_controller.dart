import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:vector_math/vector_math.dart';

import 'gamepad.dart';
import 'xbox_controller.dart';

final _log = Logger('han_dog.xbox_nc500');

/// Compatibility wrapper for the old Xbox pad and the NC500.
///
/// Both are allowed to control the robot only when Linux exposes a standard
/// /dev/input/js* joystick node. NC500's current 1a34:f517 hidraw/update mode is
/// detected but deliberately not parsed into commands.
class XboxNc500Controller implements Gamepad {
  final String joystickDevice;
  final String nc500HidrawDevice;
  final XboxConfig config;

  XboxController? _delegate;

  XboxNc500Controller(
    this.joystickDevice, {
    this.nc500HidrawDevice = '/dev/hidraw0',
    this.config = const XboxConfig(),
  });

  bool open() {
    for (final path in _joystickCandidates()) {
      final controller = XboxController(path, config: config);
      if (controller.open()) {
        _delegate = controller;
        _log.info('Xbox/NC500 joystick opened: $path');
        return true;
      }
      controller.dispose();
    }

    if (File(nc500HidrawDevice).existsSync()) {
      // ponytail: no hidraw parser until NC500's report protocol is verified on hardware.
      _log.warning(
        'NC500 receiver is present at $nc500HidrawDevice, but no /dev/input/js* '
        'joystick node is available. Control disabled until NC500 is switched '
        'to standard joystick/XInput mode.',
      );
    }
    return false;
  }

  List<String> _joystickCandidates() {
    final paths = <String>{joystickDevice};
    final inputDir = Directory('/dev/input');
    if (inputDir.existsSync()) {
      for (final entity in inputDir.listSync()) {
        final path = entity.path;
        if (path.split('/').last.startsWith('js')) {
          paths.add(path);
        }
      }
    }
    return paths.toList()..sort();
  }

  @override
  Stream<Vector3> get direction =>
      _delegate?.direction ?? Stream<Vector3>.empty();

  @override
  Stream<bool> get standup => _delegate?.standup ?? Stream<bool>.empty();

  @override
  Stream<bool> get sitdown => _delegate?.sitdown ?? Stream<bool>.empty();

  @override
  Stream<bool> get enabled => _delegate?.enabled ?? Stream<bool>.empty();

  @override
  Stream<bool> get idle => _delegate?.idle ?? Stream<bool>.empty();

  @override
  Stream<bool> get red => _delegate?.red ?? Stream<bool>.empty();

  @override
  Stream<void> get calibrate {
    // ponytail: hand controllers must not trigger SetZero; use the explicit calibration flow.
    return Stream<void>.empty();
  }

  @override
  Stream<void> get switchProfile =>
      _delegate?.switchProfile ?? Stream<void>.empty();

  @override
  void dispose() {
    _delegate?.dispose();
    _delegate = null;
  }
}
