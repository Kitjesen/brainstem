import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class OtaDevice {
  final String id;
  final String product;
  final String channel;
  final List<String> tags;
  final Map<String, String> currentVersions;
  final bool online;
  final String? lastHeartbeat;
  final String? ipAddress;

  const OtaDevice({
    required this.id, required this.product, required this.channel,
    required this.tags, required this.currentVersions, required this.online,
    this.lastHeartbeat, this.ipAddress,
  });

  factory OtaDevice.fromJson(Map<String, dynamic> j) => OtaDevice(
    id: j['id'] as String? ?? '',
    product: j['product'] as String? ?? '',
    channel: j['channel'] as String? ?? 'stable',
    tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
    currentVersions: {
      for (final e in ((j['current_versions'] as Map?) ?? {}).entries)
        e.key.toString(): e.value.toString()
    },
    online: j['online'] as bool? ?? false,
    lastHeartbeat: j['last_heartbeat'] as String?,
    ipAddress: j['ip_address'] as String?,
  );
}

class OtaPackage {
  final int id;
  final String name;
  final String version;
  final int? fileSize;
  final String? changelog;
  final String? createdAt;

  const OtaPackage({
    required this.id, required this.name, required this.version,
    this.fileSize, this.changelog, this.createdAt,
  });

  factory OtaPackage.fromJson(Map<String, dynamic> j) => OtaPackage(
    id: j['id'] as int? ?? 0,
    name: j['name'] as String? ?? '',
    version: j['version'] as String? ?? '',
    fileSize: j['file_size'] as int?,
    changelog: j['changelog'] as String?,
    createdAt: j['created_at'] as String?,
  );

  String get fileSizeLabel {
    if (fileSize == null) return '';
    final kb = fileSize! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class OtaRelease {
  final int id;
  final String version;
  final String channel;
  final String status;
  final int rolloutPercent;
  final String? createdAt;

  const OtaRelease({
    required this.id, required this.version, required this.channel,
    required this.status, required this.rolloutPercent, this.createdAt,
  });

  bool get isActive => status == 'active';

  factory OtaRelease.fromJson(Map<String, dynamic> j) => OtaRelease(
    id: j['id'] as int? ?? 0,
    version: j['version'] as String? ?? '',
    channel: j['channel'] as String? ?? 'stable',
    status: j['status'] as String? ?? 'active',
    rolloutPercent: j['rollout_percent'] as int? ?? 100,
    createdAt: j['created_at'] as String?,
  );
}

class OtaTask {
  final int id;
  final String deviceId;
  final String status;
  final int progress;
  final String? errorMessage;
  final String? createdAt;
  final String? releaseVersion;

  const OtaTask({
    required this.id, required this.deviceId, required this.status,
    required this.progress, this.errorMessage, this.createdAt, this.releaseVersion,
  });

  bool get isActive => status == 'pending' || status == 'downloading' || status == 'deploying';
  bool get isFailed => status == 'failed';
  bool get isCompleted => status == 'completed';

  factory OtaTask.fromJson(Map<String, dynamic> j) => OtaTask(
    id: j['id'] as int? ?? 0,
    deviceId: j['device_id'] as String? ?? '',
    status: j['status'] as String? ?? 'pending',
    progress: j['progress'] as int? ?? 0,
    errorMessage: j['error_message'] as String?,
    createdAt: j['created_at'] as String?,
    releaseVersion: (j['release'] as Map?)?['version'] as String?,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────

class OtaService extends ChangeNotifier {
  String baseUrl;
  String? apiKey;

  OtaService({this.baseUrl = 'https://ota.inovxio.com/api'});

  bool _loading = false;
  String? _error;
  List<OtaDevice> _devices = [];
  List<OtaPackage> _packages = [];
  List<OtaRelease> _releases = [];
  List<OtaTask> _tasks = [];
  int _alertCount = 0;

  bool get loading => _loading;
  String? get error => _error;
  List<OtaDevice> get devices => _devices;
  List<OtaPackage> get packages => _packages;
  List<OtaRelease> get releases => _releases;
  List<OtaTask> get tasks => _tasks;
  int get alertCount => _alertCount;

  final _client = HttpClient();

  String get _base {
    final b = baseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static List<T> _asList<T>(dynamic data, T Function(Map<String, dynamic>) fromJson) {
    final list = data is List
        ? data
        : data is Map
            ? (data['data'] as List? ?? data['items'] as List? ?? [])
            : <dynamic>[];
    return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<dynamic> _get(String path) async {
    final req = await _client.getUrl(Uri.parse('$_base$path'));
    if (apiKey != null) req.headers.add('X-API-Key', apiKey!);
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final req = await _client.postUrl(Uri.parse('$_base$path'));
    if (apiKey != null) req.headers.add('X-API-Key', apiKey!);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final resBody = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}: $resBody');
    return jsonDecode(resBody);
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait([
        _fetchDevices(),
        _fetchPackages(),
        _fetchReleases(),
        _fetchTasks(),
        _fetchAlertCount(),
      ]);
    } catch (e) {
      _error = '无法连接 OTA 服务器：$e';
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _fetchDevices() async {
    final data = await _get('/devices?limit=50');
    _devices = _asList(data, OtaDevice.fromJson);
  }

  Future<void> _fetchPackages() async {
    final data = await _get('/packages?limit=50');
    _packages = _asList(data, OtaPackage.fromJson);
  }

  Future<void> _fetchReleases() async {
    final data = await _get('/releases?limit=50');
    _releases = _asList(data, OtaRelease.fromJson);
  }

  Future<void> _fetchTasks() async {
    final data = await _get('/tasks?limit=50');
    _tasks = _asList(data, OtaTask.fromJson);
  }

  Future<void> _fetchAlertCount() async {
    try {
      final data = await _get('/alerts/count');
      _alertCount = (data as Map)['count'] as int? ?? 0;
    } catch (_) {
      _alertCount = 0;
    }
  }

  Future<OtaTask?> createTask(String deviceId, int releaseId) async {
    final data = await _post('/tasks/create', {
      'device_id': deviceId,
      'release_id': releaseId,
    });
    return OtaTask.fromJson(data as Map<String, dynamic>);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
