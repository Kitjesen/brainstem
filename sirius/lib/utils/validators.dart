/// Input validation utilities for the application.
class Validators {
  Validators._();

  /// Validates an IPv4 address format.
  static bool isValidIP(String ip) {
    if (ip.isEmpty) return false;
    final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (!ipRegex.hasMatch(ip)) return false;
    final parts = ip.split('.');
    return parts.every((part) {
      final num = int.tryParse(part);
      return num != null && num >= 0 && num <= 255;
    });
  }

  /// Validates a port number (1-65535).
  static bool isValidPort(String port) {
    final p = int.tryParse(port);
    return p != null && p > 0 && p <= 65535;
  }

  /// Validates a file path exists and has the correct extension.
  static bool hasValidExtension(String path, List<String> extensions) {
    final lower = path.toLowerCase();
    return extensions.any((ext) => lower.endsWith(ext));
  }

  /// Validates KP (stiffness) parameter range.
  static bool isValidKp(double value) {
    return value >= ParameterLimits.kpMin && value <= ParameterLimits.kpMax;
  }

  /// Validates KD (damping) parameter range.
  static bool isValidKd(double value) {
    return value >= ParameterLimits.kdMin && value <= ParameterLimits.kdMax;
  }

  /// Validates joint angle range (radians).
  static bool isValidJointAngle(double value) {
    return value >= ParameterLimits.jointAngleMin && value <= ParameterLimits.jointAngleMax;
  }

  /// Validates SSH username (alphanumeric, underscore, hyphen).
  static bool isValidSshUsername(String username) {
    if (username.isEmpty) return false;
    final regex = RegExp(r'^[a-zA-Z0-9_-]+$');
    return regex.hasMatch(username);
  }

  /// Validates a file path is not empty and doesn't contain invalid characters.
  static bool isValidFilePath(String path) {
    if (path.trim().isEmpty) return false;
    // Check for invalid characters (Windows + Unix)
    final invalidChars = RegExp(r'[<>"|?*\x00-\x1F]');
    return !invalidChars.hasMatch(path);
  }
}

/// Parameter limits for robot configuration.
class ParameterLimits {
  ParameterLimits._();

  static const double kpMin = 0.0;
  static const double kpMax = 300.0;
  static const double kdMin = 0.0;
  static const double kdMax = 20.0;
  static const double jointAngleMin = -3.14159; // -180 degrees
  static const double jointAngleMax = 3.14159;  // 180 degrees

  static const double imuGyroScaleMin = 0.01;
  static const double imuGyroScaleMax = 2.0;

  static const int historyMin = 1;
  static const int historyMax = 20;

  static const int standUpCountsMin = 10;
  static const int standUpCountsMax = 500;

  static const int sitDownCountsMin = 10;
  static const int sitDownCountsMax = 500;

  static const double velocityScaleMin = 0.001;
  static const double velocityScaleMax = 1.0;

  static const double actionScaleMin = 0.01;
  static const double actionScaleMax = 10.0;
}

/// Control input processing utilities.
class ControlUtils {
  ControlUtils._();

  static const double deadzone = 0.05; // 5% deadzone
  static const double maxSpeed = 1.0;
  static const double maxRotation = 1.0;

  /// Applies deadzone to joystick input.
  static double applyDeadzone(double value) {
    if (value.abs() < deadzone) return 0.0;
    return value;
  }

  /// Clamps speed value to safe range.
  static double clampSpeed(double value) {
    return value.clamp(-maxSpeed, maxSpeed);
  }

  /// Clamps rotation value to safe range.
  static double clampRotation(double value) {
    return value.clamp(-maxRotation, maxRotation);
  }
}
