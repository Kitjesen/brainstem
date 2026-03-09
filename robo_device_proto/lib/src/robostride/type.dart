enum RSBaudRate {
  rate1M(1),
  rate500K(2),
  rate250K(3),
  rate125K(4);

  final int value;
  const RSBaudRate(this.value);
}

enum RSProtocol {
  private(0),
  canopen(1),
  mit(2);

  final int value;
  const RSProtocol(this.value);
}

enum RSRunMode {
  control(0), // 运控模式
  pp(1), // 位置模式
  velocity(2), // 速度模式
  torque(3), // 力矩模式
  csp(5); // 位置闭环模式

  final int value;
  const RSRunMode(this.value);

  static RSRunMode fromValue(int value) {
    return .values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => throw ArgumentError('Invalid RunMode value: $value'),
    );
  }

  @override
  String toString() {
    return switch (this) {
      control => 'Control',
      pp => 'Position(PP)',
      velocity => 'Velocity',
      torque => 'Torque',
      csp => 'Position(CSP)',
    };
  }
}

enum RSStatus {
  reset(0),
  calibration(1),
  motor(2),
  unknown(3);

  final int value;
  const RSStatus(this.value);

  static RSStatus fromValue(int value) {
    return .values.firstWhere(
      (status) => status.value == value,
      orElse: () => .unknown,
    );
  }
}
