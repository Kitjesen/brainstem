/// 电机故障代码（RS04 手册 §3.3.7 功能码 0x3022）
enum RSError {
  overTemperature, // bit0: 过温 >145°C
  driverFault, // bit1: 驱动芯片故障
  underVoltage, // bit2: 欠压 <12V
  overVoltage, // bit3: 过压 >60V
  phaseBOverCurrent, // bit4: B相电流过流
  phaseCOverCurrent, // bit5: C相电流过流
  uncalibrated, // bit7: 编码器未标定
  hardwareIdFault, // bit8: 硬件识别故障
  posInitFault, // bit9: 位置初始化故障
  stallOverload, // bit14: 堵转过载保护
  phaseAOverCurrent, // bit16: A相电流过流
  magneticEncoderFault, // 磁编码故障（兼容旧代码）
}

/// 故障清除方法（RS04 手册 §4.1 通信类型 4）：
/// 发送通信类型 4（停止运行）+ Byte[0]=1 即可清除故障。
/// 代码中对应：`disable(canId, clearErrors: true)`
/// 清除后需重新 `enable(canId)` 才能恢复运行。
///
/// 自动恢复流程：
/// 1. 检测到故障 → MotorHealthManager 标记 degraded/critical
/// 2. FSM 切到 Grounded 状态
/// 3. 调用 clearFaultSingle(idx) → disable(clearErrors: true)
/// 4. 重新 enable()
/// 5. 确认故障清除后恢复控制

/// 通信类型 2 反馈帧中 bit16~21 的故障标志（旧协议格式）
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

/// 功能码 0x3022 故障码（完整 17 bit，对应手册 §3.3.7）
extension type RSErrors2(int value) {
  factory RSErrors2.none() => .new(0);

  static const _fromCode = <int, RSError>{
    0: .overTemperature, // 过温 >145°C
    1: .driverFault, // 驱动芯片故障
    2: .underVoltage, // 欠压 <12V
    3: .overVoltage, // 过压 >60V
    4: .phaseBOverCurrent, // B相电流过流
    5: .phaseCOverCurrent, // C相电流过流
    7: .uncalibrated, // 编码器未标定
    8: .hardwareIdFault, // 硬件识别故障
    9: .posInitFault, // 位置初始化故障
    14: .stallOverload, // 堵转过载保护
    16: .phaseAOverCurrent, // A相电流过流
  };

  static bool _isPresent(int faultBits, int bit) {
    return (faultBits & (1 << bit)) != 0;
  }

  Set<RSError> get errors => _fromCode.entries
      .where((entry) => _isPresent(value, entry.key))
      .map((entry) => entry.value)
      .toSet();
}
