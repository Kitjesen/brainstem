import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:han_dog_message/han_dog_message.dart' hide Duration;

enum RecordState { idle, recording, saving }

/// Records IMU and joint data to a CSV file.
class DataRecorder extends ChangeNotifier {
  RecordState _state = RecordState.idle;
  RecordState get state => _state;
  bool get isRecording => _state == RecordState.recording;

  int _frameCount = 0;
  int get frameCount => _frameCount;

  DateTime? _startTime;
  Duration get elapsed =>
      _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

  String? _lastSavedPath;
  String? get lastSavedPath => _lastSavedPath;

  // Raw lines buffer (header + data rows)
  final List<String> _lines = [];

  static const _header =
      'timestamp_ms,imu_qw,imu_qx,imu_qy,imu_qz,'
      'gyro_x,gyro_y,gyro_z,'
      'grav_x,grav_y,grav_z,'
      'j0_pos,j1_pos,j2_pos,j3_pos,j4_pos,j5_pos,j6_pos,j7_pos,'
      'j8_pos,j9_pos,j10_pos,j11_pos,j12_pos,j13_pos,j14_pos,j15_pos,'
      'j0_vel,j1_vel,j2_vel,j3_vel,j4_vel,j5_vel,j6_vel,j7_vel,'
      'j8_vel,j9_vel,j10_vel,j11_vel,j12_vel,j13_vel,j14_vel,j15_vel,'
      'j0_trq,j1_trq,j2_trq,j3_trq,j4_trq,j5_trq,j6_trq,j7_trq,'
      'j8_trq,j9_trq,j10_trq,j11_trq,j12_trq,j13_trq,j14_trq,j15_trq';

  void startRecording() {
    if (_state != RecordState.idle) return;
    _lines.clear();
    _lines.add(_header);
    _frameCount = 0;
    _startTime = DateTime.now();
    _state = RecordState.recording;
    notifyListeners();
  }

  /// Feed a frame of data. Call this from a gRPC listener each tick.
  void recordFrame({Imu? imu, AllJoints? joints}) {
    if (_state != RecordState.recording) return;

    final ts = DateTime.now().millisecondsSinceEpoch;

    // IMU fields
    final q = imu?.hasQuaternion() == true ? imu!.quaternion : null;
    final qw = q?.w ?? 0.0, qx = q?.x ?? 0.0, qy = q?.y ?? 0.0, qz = q?.z ?? 0.0;
    final gyro = imu?.hasGyroscope() == true ? imu!.gyroscope : null;
    final gx = gyro?.x ?? 0.0, gy = gyro?.y ?? 0.0, gz = gyro?.z ?? 0.0;
    // projectedGravity is in History, not Imu; record zeros here
    const pgx = 0.0, pgy = 0.0, pgz = 0.0;

    // Joint fields (16 joints each)
    String jointsStr(List<double> vals) =>
        List.generate(16, (i) => i < vals.length ? vals[i].toStringAsFixed(4) : '0')
            .join(',');

    final pos = jointsStr(joints?.position.values ?? []);
    final vel = jointsStr(joints?.velocity.values ?? []);
    final trq = jointsStr(joints?.torque.values ?? []);

    _lines.add('$ts,'
        '${qw.toStringAsFixed(4)},${qx.toStringAsFixed(4)},${qy.toStringAsFixed(4)},${qz.toStringAsFixed(4)},'
        '${gx.toStringAsFixed(4)},${gy.toStringAsFixed(4)},${gz.toStringAsFixed(4)},'
        '${pgx.toStringAsFixed(4)},${pgy.toStringAsFixed(4)},${pgz.toStringAsFixed(4)},'
        '$pos,$vel,$trq');

    _frameCount++;
    // Notify every 10 frames to avoid excessive rebuilds
    if (_frameCount % 10 == 0) notifyListeners();
  }

  /// Stop recording and save to [path]. Returns the saved path on success.
  Future<String?> stopAndSave(String path) async {
    if (_state != RecordState.recording) return null;
    _state = RecordState.saving;
    notifyListeners();

    try {
      final file = File(path);
      await file.writeAsString(_lines.join('\n'));
      _lastSavedPath = path;
      _state = RecordState.idle;
      notifyListeners();
      return path;
    } catch (e) {
      _state = RecordState.idle;
      notifyListeners();
      rethrow;
    }
  }

  void cancelRecording() {
    _lines.clear();
    _frameCount = 0;
    _startTime = null;
    _state = RecordState.idle;
    notifyListeners();
  }

  static Future<String> defaultSavePath() async {
    final ts = DateTime.now();
    final stamp =
        '${ts.year}${_p(ts.month)}${_p(ts.day)}_${_p(ts.hour)}${_p(ts.minute)}${_p(ts.second)}';
    final String dir;
    if (Platform.isWindows) {
      final docs = Platform.environment['USERPROFILE'] ?? '';
      dir = '$docs\\Documents\\nova_dog_recordings';
    } else {
      dir = '${Platform.environment['HOME']}/nova_dog_recordings';
    }
    await Directory(dir).create(recursive: true);
    return '$dir${Platform.pathSeparator}recording_$stamp.csv';
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}
