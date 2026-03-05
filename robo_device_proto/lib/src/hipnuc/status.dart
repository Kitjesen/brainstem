/// HIPNUC IMU 状态字枚举
/// 对应状态字说明表中的各个位定义
enum HipnucStatus {
  /// 位0-4: 保留
  reserved0(0),
  reserved1(1),
  reserved2(2),
  reserved3(3),
  reserved4(4),

  /// 位5: RANGE_WARN - 加速度计或陀螺过大过速入量程
  rangeWarn(5),

  /// 位6: ATT_WARN - 保留
  attWarn(6),

  /// 位7: BIAS_WARN - 保留
  biasWarn(7),

  /// 位8: MAG_DIST_STAT - 当前地磁环境良好或系统处于6轴模式
  magDistStat(8),

  /// 位9: MAG_AIDING - 磁传感器不参与航向计算(6轴模式)
  magAiding(9),

  /// 位10: POS_WARN - 位置精度正常,或产品不支持位置输出
  posWarn(10),

  /// 位12: SOUT_PULSE_FLAG - 当前数据帧没有SOUT脉冲输出
  soutPulseFlag(12);

  const HipnucStatus(this.bit);

  /// 对应的位位置
  final int bit;

  /// 对应的位值
  int get value => 1 << bit;
}

extension type const HipnucStatusFlags(int value) {
  /// 获取所有激活的状态标志
  List<HipnucStatus> get all =>
      HipnucStatus.values.where((s) => (value & s.value) != 0).toList();

  bool has(HipnucStatus status) => (value & status.value) != 0;
  HipnucStatusFlags add(HipnucStatus status) => .new(value | status.value);
  HipnucStatusFlags remove(HipnucStatus status) => .new(value & ~status.value);

  HipnucStatusFlags operator &(HipnucStatusFlags other) =>
      .new(value & other.value);
  HipnucStatusFlags operator |(HipnucStatusFlags other) =>
      .new(value | other.value);

  /// 检查基础数据采集相关状态
  bool get hasRangeWarning => has(.rangeWarn);

  /// 检查地磁环境状态 (0表示当前地磁环境良好或系统处于6轴模式)
  bool get magEnvironmentGood => !has(.magDistStat);

  /// 检查地磁辅合标志 (1表示磁传感器提正在参与航向[9轴模式])
  bool get magAidingEnabled => !has(.magAiding);

  /// 检查位置误差指示 (0表示位置精度正常,或产品不支持位置输出)
  bool get positionAccuracyGood => !has(.posWarn);

  /// 检查SOUT脉冲输出状态 (0表示当前数据帧没有SOUT脉冲输出)
  bool get soutPulseOutput => !has(.soutPulseFlag);
}
