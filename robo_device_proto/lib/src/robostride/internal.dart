import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:robo_device_proto/src/can_frame.dart';

const double positionMax = 12.57;
const double velocityMax = 15.0;
const double torqueMax = 120.0;
const double kpMax = 5000.0;
const double kdMax = 100.0;

class RSDataFrame extends Equatable {
  final int mode; // Bit28~24
  final int data2; // Bit23~8
  final int canId; // Bit7~0
  final Uint8List data1; // Byte0~Byte7
  late final bytes = ByteData.sublistView(data1);

  @override
  List<Object?> get props => [mode, data2, canId, data1];

  RSDataFrame({
    required this.mode,
    required this.data2,
    required this.canId,
    Uint8List? data1,
  }) : data1 = data1 ?? Uint8List(8) {
    assert(this.data1.length == 8, 'Data length must be 8 bytes');
  }
  factory RSDataFrame.fromCanFrame(CanFrame frame) => RSDataFrame(
    mode: (frame.id >> 24) & 0xFF,
    data2: (frame.id >> 8) & 0xFFFF,
    canId: frame.id & 0xFF,
    data1: frame.data,
  );
  CanFrame toCanFrame() => CanFrame(
    id: mode << 24 | data2 << 8 | canId,
    type: CanType.extended,
    data: data1,
  );

  @override
  String toString() {
    return 'RawData(mode: $mode, '
        'data2: 0x${data2.toRadixString(16)}, '
        'targetId: $canId, '
        'data1: ${data1.toHexString()})';
  }

  String toHexString() {
    final id = mode << 24 | data2 << 8 | canId;
    final data = data1
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('');
    return '${id.toRadixString(16).padLeft(8, '0')}08$data';
  }
}

extension Uint8ListPrint on Uint8List {
  String toHexString() {
    return map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}

/// 通用映射函数：将物理值映射到 uint16 (0~65535) 范围
///
/// [value] - 要映射的物理值
/// [min] - 物理值范围的最小值
/// [max] - 物理值范围的最大值
int floatToUint16(double value, double min, double max) {
  // 确保值在指定范围内
  value = value.clamp(min, max);
  // 计算映射后的值
  return ((value - min) / (max - min) * 65535).round().clamp(0, 65535);
}

double uint16ToFloat(int value, double min, double max) {
  // 确保值在 uint16 范围内
  value = value.clamp(0, 65535);
  // 计算映射后的物理值
  return min + (value / 65535) * (max - min);
}
