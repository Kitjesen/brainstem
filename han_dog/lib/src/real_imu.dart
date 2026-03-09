import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:vector_math/vector_math.dart';
import 'package:frequency_watch/frequency_watch.dart';
import 'package:han_dog_brain/han_dog_brain.dart';

final _log = Logger('han_dog.real_imu');

class RealImu implements ImuService {
  final String portName;
  final SerialPortController<Hi91Event, Hi91State> port;

  @override
  var gyroscope = Vector3.zero();
  @override
  var projectedGravity = Vector3(0, 0, -1);
  @override
  Vector3 get initialGyroscope => .zero();
  @override
  Vector3 get initialProjectedGravity => .new(0, 0, -1);

  // 复用缓冲，避免每帧分配 Vector3 对象
  final _gyroBuffer = Vector3.zero();
  final _gravBuffer = Vector3(0, 0, -1);

  final hz = RealFrequency();

  /// 最后一次收到 IMU 数据的时间戳。null 表示从未收到数据。
  DateTime? lastUpdate;

  /// IMU 数据是否已过期（超过 200ms 未更新）。
  bool get isStale =>
      lastUpdate == null ||
      DateTime.now().difference(lastUpdate!).inMilliseconds > 200;

  /// 当 IMU 串口流发生错误或意外关闭时调用的回调。
  /// 由外部（如 han_dog.dart）设置，用于将传感器断联事件转发为 FSM Fault。
  void Function(String reason)? onDisconnect;

  late final StreamSubscription<Iterable<Hi91State>> subs;

  /// 广播流控制器：port.state 是单订阅流，这里转发为广播流，
  /// 让 gRPC 服务和其他消费者都能同时订阅。
  final _broadcastController = StreamController<Iterable<Hi91State>>.broadcast();

  /// 广播流：支持多个订阅者（gRPC 客户端、App 断线重连等）
  Stream<Iterable<Hi91State>> get stateStream => _broadcastController.stream;

  RealImu([this.portName = '/dev/ttyUSB0']) : port = .new(portName) {
    subs = port.state.listen(
      (data) {
        // 转发到广播流（在过滤之前，保证所有数据对外可见）
        _broadcastController.add(data);
        if (data.isEmpty) return;
        lastUpdate = DateTime.now();
        final imuData = data.last;
        hz.add(data.length);
        _gyroBuffer.setValues(
          _degreeToRadius(imuData.gyroscope.x),
          _degreeToRadius(imuData.gyroscope.y),
          _degreeToRadius(imuData.gyroscope.z),
        );
        gyroscope = _gyroBuffer;
        _gravBuffer.setValues(0, 0, -1);
        imuData.quaternion.rotate(_gravBuffer);
        projectedGravity = _gravBuffer;
      },
      onError: (Object error, StackTrace st) {
        _log.severe('IMU port stream error', error, st);
        onDisconnect?.call('IMU stream error: $error');
      },
      onDone: () {
        _log.warning('IMU port stream closed unexpectedly');
        onDisconnect?.call('IMU stream closed');
      },
    );
  }

  bool open() {
    final ok = port.open();
    if (ok) {
      _log.info('IMU opened: $portName');
    } else {
      _log.severe('IMU open failed: $portName');
    }
    return ok;
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _log.info('IMU disposing: $portName');
    subs.cancel();
    _broadcastController.close();
    port.dispose();
  }

  @override
  String toString() {
    return 'Imu gyro: $gyroscope, proj: $projectedGravity';
  }
}

double _degreeToRadius(double degree) => degree / 180 * pi;
