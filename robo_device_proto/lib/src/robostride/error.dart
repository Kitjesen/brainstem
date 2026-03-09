/// 电机故障代码
enum RSError {
  underVoltage, // 欠压故障
  overVoltage, // 过压故障
  driverFault, // 驱动故障
  overTemperature, // 过温
  magneticEncoderFault, // 磁编码故障
  stallOverload, // 堵转过载故障
  uncalibrated, // 未标定
}

extension type RSErrors1(int value) {
  factory RSErrors1.none() => .new(0);

  static const _fromCode = <int, RSError>{
    16: .underVoltage,
    17: .driverFault,
    18: .overTemperature,
    19: .magneticEncoderFault,
    20: .stallOverload,
    21: .uncalibrated,
  };
  static bool _isPresent(int faultBits, int bit) {
    return (faultBits & (1 << (bit - 16))) != 0;
  }

  Set<RSError> get errors => _fromCode.entries
      .where((entry) => _isPresent(value, entry.key))
      .map((entry) => entry.value)
      .toSet();
}
extension type RSErrors2(int value) {
  factory RSErrors2.none() => .new(0);

  static const _fromCode = <int, RSError>{
    0: .overTemperature,
    1: .driverFault,
    2: .underVoltage,
    3: .overVoltage,
    7: .uncalibrated,
    14: .stallOverload,
  };

  static bool _isPresent(int faultBits, int bit) {
    return (faultBits & (1 << bit)) != 0;
  }

  Set<RSError> get errors => _fromCode.entries
      .where((entry) => _isPresent(value, entry.key))
      .map((entry) => entry.value)
      .toSet();
}
