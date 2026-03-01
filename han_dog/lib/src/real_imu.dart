import 'dart:async';
import 'dart:math';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:vector_math/vector_math.dart';
import 'package:frequency_watch/frequency_watch.dart';
import 'package:han_dog_brain/han_dog_brain.dart';

class RealImu implements ImuService {
  final SerialPortController<Hi91Event, Hi91State> port;

  @override
  var gyroscope = Vector3.zero();
  @override
  var projectedGravity = Vector3(0, 0, -1);
  @override
  Vector3 get initialGyroscope => .zero();
  @override
  Vector3 get initialProjectedGravity => .new(0, 0, -1);

  final hz = RealFrequency();

  late final StreamSubscription<Iterable<Hi91State>> subs;

  /// 广播流控制器：port.state 是单订阅流，这里转发为广播流，
  /// 让 gRPC 服务和其他消费者都能同时订阅。
  final _broadcastController = StreamController<Iterable<Hi91State>>.broadcast();

  /// 广播流：支持多个订阅者（gRPC 客户端、App 断线重连等）
  Stream<Iterable<Hi91State>> get stateStream => _broadcastController.stream;

  RealImu([String portName = '/dev/ttyUSB0']) : port = .new(portName) {
    subs = port.state.listen((data) {
      // 转发到广播流（在过滤之前，保证所有数据对外可见）
      _broadcastController.add(data);
      if (data.isEmpty) return;
      final imuData = data.last;
      hz.add(data.length);
      gyroscope = .new(
        _degreeToRadius(imuData.gyroscope.x),
        _degreeToRadius(imuData.gyroscope.y),
        _degreeToRadius(imuData.gyroscope.z),
      );
      projectedGravity = imuData.quaternion.rotate(.new(0, 0, -1));
    });
  }

  bool open() {
    return port.open();
  }

  void dispose() {
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
