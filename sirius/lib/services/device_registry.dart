import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class DeviceInfo {
  final String name; // user-given label
  final String ip;
  final int port;
  final DateTime? lastConnected;

  const DeviceInfo({
    required this.name,
    required this.ip,
    required this.port,
    this.lastConnected,
  });

  DeviceInfo copyWith({String? name, DateTime? lastConnected}) => DeviceInfo(
        name: name ?? this.name,
        ip: ip,
        port: port,
        lastConnected: lastConnected ?? this.lastConnected,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        'port': port,
        'lastConnected': lastConnected?.toIso8601String(),
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        name: j['name'] as String? ?? j['ip'] as String,
        ip: j['ip'] as String,
        port: j['port'] as int? ?? 13145,
        lastConnected: j['lastConnected'] != null
            ? DateTime.tryParse(j['lastConnected'] as String)
            : null,
      );

  String get addressLabel => '$ip:$port';
}

/// Persists a list of favourite robot devices to a JSON file.
class DeviceRegistry extends ChangeNotifier {
  List<DeviceInfo> _devices = [];
  List<DeviceInfo> get devices => List.unmodifiable(_devices);

  // ── Storage ──

  static Future<File> _storageFile() async {
    final String dir;
    if (Platform.isWindows) {
      dir = '${Platform.environment['APPDATA']}\\nova_dog';
    } else {
      dir = '${Platform.environment['HOME']}/.nova_dog';
    }
    await Directory(dir).create(recursive: true);
    return File('$dir/devices.json');
  }

  Future<void> load() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _devices = list
          .map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final file = await _storageFile();
      await file.writeAsString(
          jsonEncode(_devices.map((d) => d.toJson()).toList()));
    } catch (_) {}
  }

  // ── Public API ──

  /// Adds or updates a device (matched by ip+port).
  Future<void> save(DeviceInfo device) async {
    final idx = _devices.indexWhere((d) => d.ip == device.ip && d.port == device.port);
    if (idx >= 0) {
      _devices[idx] = device;
    } else {
      _devices.insert(0, device);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String ip, int port) async {
    _devices.removeWhere((d) => d.ip == ip && d.port == port);
    notifyListeners();
    await _persist();
  }

  /// Bumps lastConnected timestamp for the matching device.
  Future<void> touch(String ip, int port) async {
    final idx = _devices.indexWhere((d) => d.ip == ip && d.port == port);
    if (idx >= 0) {
      _devices[idx] = _devices[idx].copyWith(lastConnected: DateTime.now());
      notifyListeners();
      await _persist();
    }
  }

  bool isSaved(String ip, int port) =>
      _devices.any((d) => d.ip == ip && d.port == port);
}
