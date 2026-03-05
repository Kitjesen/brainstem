import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vector_math/vector_math.dart';
import 'status.dart';

part 'state.freezed.dart';

@freezed
abstract class Hi91State with _$Hi91State {
  factory Hi91State({
    required HipnucStatusFlags status,
    required int temperature,
    required double airPressure,
    required int timeStamp,
    required Vector3 acceleration,
    required Vector3 gyroscope,
    required Vector3 magneticField,
    required double roll,
    required double pitch,
    required double yaw,
    required Quaternion quaternion,
  }) = _Hi91State;

  factory Hi91State.fromBytes(Uint8List bytes) {
    if (bytes.length < 76) {
      throw ArgumentError(
        'Hi91State: data too short (${bytes.length} < 76)',
      );
    }
    final dataView = ByteData.sublistView(bytes);

    return Hi91State(
      status: .new(dataView.getUint16(1, .little)),
      temperature: dataView.getInt8(3),
      airPressure: dataView.getFloat32(4, .little),
      timeStamp: dataView.getUint32(8, .little),
      acceleration: .new(
        dataView.getFloat32(12, .little),
        dataView.getFloat32(16, .little),
        dataView.getFloat32(20, .little),
      ),
      gyroscope: .new(
        dataView.getFloat32(24, .little),
        dataView.getFloat32(28, .little),
        dataView.getFloat32(32, .little),
      ),
      magneticField: .new(
        dataView.getFloat32(36, .little),
        dataView.getFloat32(40, .little),
        dataView.getFloat32(44, .little),
      ),
      roll: dataView.getFloat32(48, .little),
      pitch: dataView.getFloat32(52, .little),
      yaw: dataView.getFloat32(56, .little),
      quaternion: .new(
        dataView.getFloat32(64, .little),
        dataView.getFloat32(68, .little),
        dataView.getFloat32(72, .little),
        dataView.getFloat32(60, .little),
      ),
    );
  }
}
