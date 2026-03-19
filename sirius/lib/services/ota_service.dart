import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

// ── Data models ─────────────────────────────────────────────────────────────

class OtaDevice {
  final String id;
  final String product;
  final String channel;
  final List<String> tags;
  final Map<String, String> currentVersions;
  final bool online;
  final String? lastHeartbeat;
  final String? ipAddress;
  final String? serialNumber;
  final String? customerId;
  final String lifecycleStatus;
  final String? location;

  const OtaDevice({
    required this.id, required this.product, required this.channel,
    required this.tags, required this.currentVersions, required this.online,
    this.lastHeartbeat, this.ipAddress, this.serialNumber, this.customerId,
    this.lifecycleStatus = 'active', this.location,
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
    serialNumber: j['serial_number'] as String?,
    customerId: j['customer_id'] as String?,
    lifecycleStatus: j['lifecycle_status'] as String? ?? 'active',
    location: j['location'] as String?,
  );
}

class OtaPackage {
  final int id;
  final String name;
  final String version;
  final String? filename;
  final int? fileSize;
  final String? sha256;
  final String? changelog;
  final String? createdAt;

  const OtaPackage({
    required this.id, required this.name, required this.version,
    this.filename, this.fileSize, this.sha256, this.changelog, this.createdAt,
  });

  factory OtaPackage.fromJson(Map<String, dynamic> j) => OtaPackage(
    id: j['id'] as int? ?? 0,
    name: j['name'] as String? ?? '',
    version: j['version'] as String? ?? '',
    filename: j['filename'] as String?,
    fileSize: j['file_size'] as int?,
    sha256: j['sha256'] as String?,
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
  final bool forceUpdate;
  final bool circuitBreakerTriggered;
  final List<String> targetTags;
  final List<String> targetDevices;
  final String? createdAt;

  const OtaRelease({
    required this.id, required this.version, required this.channel,
    required this.status, required this.rolloutPercent,
    this.forceUpdate = false, this.circuitBreakerTriggered = false,
    this.targetTags = const [], this.targetDevices = const [],
    this.createdAt,
  });

  bool get isActive => status == 'active';
  bool get isRolledBack => status == 'rolled_back';

  factory OtaRelease.fromJson(Map<String, dynamic> j) => OtaRelease(
    id: j['id'] as int? ?? 0,
    version: j['version'] as String? ?? '',
    channel: j['channel'] as String? ?? 'stable',
    status: j['status'] as String? ?? 'active',
    rolloutPercent: j['rollout_percent'] as int? ?? 100,
    forceUpdate: j['force_update'] as bool? ?? false,
    circuitBreakerTriggered: j['circuit_breaker_triggered'] as bool? ?? false,
    targetTags: (j['target_tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
    targetDevices: (j['target_devices'] as List?)?.map((e) => e.toString()).toList() ?? [],
    createdAt: j['created_at'] as String?,
  );
}

class OtaTask {
  final String id;
  final String deviceId;
  final int releaseId;
  final String status;
  final int progressPercent;
  final String? errorMessage;
  final String? startedAt;
  final String? completedAt;

  const OtaTask({
    required this.id, required this.deviceId, required this.releaseId,
    required this.status, required this.progressPercent,
    this.errorMessage, this.startedAt, this.completedAt,
  });

  bool get isActive =>
      status == 'pending' || status == 'downloading' || status == 'installing';
  bool get isFailed => status == 'failed';
  bool get isCompleted => status == 'success';

  factory OtaTask.fromJson(Map<String, dynamic> j) => OtaTask(
    id: (j['id'] ?? '').toString(),
    deviceId: j['device_id'] as String? ?? '',
    releaseId: j['release_id'] as int? ?? 0,
    status: j['status'] as String? ?? 'pending',
    progressPercent: j['progress_percent'] as int? ?? 0,
    errorMessage: j['error_message'] as String?,
    startedAt: j['started_at'] as String?,
    completedAt: j['completed_at'] as String?,
  );
}

class OtaAlert {
  final int id;
  final String alertType;
  final String severity;
  final String message;
  final String? deviceId;
  final String? taskId;
  final int? releaseId;
  final Map<String, dynamic> metadata;
  final String? createdAt;
  final bool acknowledged;
  final String? acknowledgedAt;
  final String? acknowledgedBy;

  const OtaAlert({
    required this.id, required this.alertType, required this.severity,
    required this.message, this.deviceId, this.taskId, this.releaseId,
    this.metadata = const {}, this.createdAt,
    this.acknowledged = false, this.acknowledgedAt, this.acknowledgedBy,
  });

  bool get isCritical => severity == 'critical';
  bool get isWarning => severity == 'warning';

  factory OtaAlert.fromJson(Map<String, dynamic> j) => OtaAlert(
    id: j['id'] as int? ?? 0,
    alertType: j['alert_type'] as String? ?? '',
    severity: j['severity'] as String? ?? 'info',
    message: j['message'] as String? ?? '',
    deviceId: j['device_id'] as String?,
    taskId: j['task_id'] as String?,
    releaseId: j['release_id'] as int?,
    metadata: (j['metadata'] as Map<String, dynamic>?) ?? {},
    createdAt: j['created_at'] as String?,
    acknowledged: j['acknowledged'] as bool? ?? false,
    acknowledgedAt: j['acknowledged_at'] as String?,
    acknowledgedBy: j['acknowledged_by'] as String?,
  );
}

class OtaTelemetry {
  final int id;
  final String deviceId;
  final double? cpuLoad1m;
  final double? cpuLoad5m;
  final double? cpuTemp;
  final double? memUsedPercent;
  final double? diskUsedPercent;
  final double? batteryPercent;
  final Map<String, double>? jointTemps;
  final String? collectedAt;

  const OtaTelemetry({
    required this.id, required this.deviceId,
    this.cpuLoad1m, this.cpuLoad5m, this.cpuTemp,
    this.memUsedPercent, this.diskUsedPercent, this.batteryPercent,
    this.jointTemps, this.collectedAt,
  });

  factory OtaTelemetry.fromJson(Map<String, dynamic> j) => OtaTelemetry(
    id: j['id'] as int? ?? 0,
    deviceId: j['device_id'] as String? ?? '',
    cpuLoad1m: (j['cpu_load_1m'] as num?)?.toDouble(),
    cpuLoad5m: (j['cpu_load_5m'] as num?)?.toDouble(),
    cpuTemp: (j['cpu_temp_c'] as num?)?.toDouble(),
    memUsedPercent: (j['mem_used_percent'] as num?)?.toDouble(),
    diskUsedPercent: (j['disk_used_percent'] as num?)?.toDouble(),
    batteryPercent: (j['battery_percent'] as num?)?.toDouble(),
    jointTemps: (j['joint_temps'] as Map?)?.map(
        (k, v) => MapEntry<String, double>(k.toString(), (v as num).toDouble())),
    collectedAt: j['collected_at'] as String?,
  );
}

class OtaDeviceHealth {
  final String deviceId;
  final OtaTelemetry? latest;
  final double? healthScore;
  final List<String> alerts;
  final String? lastSeen;

  const OtaDeviceHealth({
    required this.deviceId, this.latest, this.healthScore,
    this.alerts = const [], this.lastSeen,
  });

  factory OtaDeviceHealth.fromJson(Map<String, dynamic> j) => OtaDeviceHealth(
    deviceId: j['device_id'] as String? ?? '',
    latest: j['latest'] != null
        ? OtaTelemetry.fromJson(j['latest'] as Map<String, dynamic>)
        : null,
    healthScore: (j['health_score'] as num?)?.toDouble(),
    alerts: (j['alerts'] as List?)?.map((e) => e.toString()).toList() ?? [],
    lastSeen: j['last_seen'] as String?,
  );
}

class OtaRollbackCommand {
  final int id;
  final List<String> targetDeviceIds;
  final String packageName;
  final String targetVersion;
  final String? reason;
  final bool force;
  final String? initiatedBy;
  final String status;
  final Map<String, int> progress;
  final String? createdAt;
  final String? completedAt;

  const OtaRollbackCommand({
    required this.id, required this.targetDeviceIds,
    required this.packageName, required this.targetVersion,
    this.reason, this.force = false, this.initiatedBy,
    required this.status, this.progress = const {},
    this.createdAt, this.completedAt,
  });

  factory OtaRollbackCommand.fromJson(Map<String, dynamic> j) =>
      OtaRollbackCommand(
        id: j['id'] as int? ?? 0,
        targetDeviceIds: (j['target_device_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        packageName: j['package_name'] as String? ?? '',
        targetVersion: j['target_version'] as String? ?? '',
        reason: j['reason'] as String?,
        force: j['force'] as bool? ?? false,
        initiatedBy: j['initiated_by'] as String?,
        status: j['status'] as String? ?? 'pending',
        progress: (j['progress'] as Map?)?.map(
                (k, v) => MapEntry<String, int>(k.toString(), v as int)) ??
            {},
        createdAt: j['created_at'] as String?,
        completedAt: j['completed_at'] as String?,
      );
}

class OtaDiagCommand {
  final int id;
  final String deviceId;
  final String commandType;
  final Map<String, dynamic> params;
  final String status;
  final String? errorMessage;
  final String? createdAt;
  final String? executedAt;
  final String? completedAt;

  const OtaDiagCommand({
    required this.id, required this.deviceId, required this.commandType,
    this.params = const {}, required this.status,
    this.errorMessage, this.createdAt, this.executedAt, this.completedAt,
  });

  factory OtaDiagCommand.fromJson(Map<String, dynamic> j) => OtaDiagCommand(
    id: j['id'] as int? ?? 0,
    deviceId: j['device_id'] as String? ?? '',
    commandType: j['command_type'] as String? ?? '',
    params: (j['params'] as Map<String, dynamic>?) ?? {},
    status: j['status'] as String? ?? 'pending',
    errorMessage: j['error_message'] as String?,
    createdAt: j['created_at'] as String?,
    executedAt: j['executed_at'] as String?,
    completedAt: j['completed_at'] as String?,
  );
}

class OtaDeviceConfig {
  final int id;
  final String? deviceId;
  final int? groupId;
  final String configKey;
  final Map<String, dynamic> configValue;
  final String version;
  final String status;
  final String? appliedAt;
  final String? createdAt;

  const OtaDeviceConfig({
    required this.id, this.deviceId, this.groupId,
    required this.configKey, required this.configValue,
    required this.version, required this.status,
    this.appliedAt, this.createdAt,
  });

  factory OtaDeviceConfig.fromJson(Map<String, dynamic> j) => OtaDeviceConfig(
    id: j['id'] as int? ?? 0,
    deviceId: j['device_id'] as String?,
    groupId: j['group_id'] as int?,
    configKey: j['config_key'] as String? ?? '',
    configValue: (j['config_value'] as Map<String, dynamic>?) ?? {},
    version: j['version'] as String? ?? '',
    status: j['status'] as String? ?? 'pending',
    appliedAt: j['applied_at'] as String?,
    createdAt: j['created_at'] as String?,
  );
}

// ── Service ─────────────────────────────────────────────────────────────────

class OtaService extends ChangeNotifier {
  String baseUrl;
  String? apiKey;

  OtaService({this.baseUrl = 'https://ota.inovxio.com/api'});

  static const _getTimeout = Duration(seconds: 10);
  static const _postTimeout = Duration(seconds: 15);

  bool _isDisposed = false;
  bool _loading = false;
  String? _error;
  List<OtaDevice> _devices = [];
  List<OtaPackage> _packages = [];
  List<OtaRelease> _releases = [];
  List<OtaTask> _tasks = [];
  List<OtaAlert> _alerts = [];
  int _alertCount = 0;

  bool get loading => _loading;
  String? get error => _error;
  List<OtaDevice> get devices => _devices;
  List<OtaPackage> get packages => _packages;
  List<OtaRelease> get releases => _releases;
  List<OtaTask> get tasks => _tasks;
  List<OtaAlert> get alerts => _alerts;
  int get alertCount => _alertCount;

  final _client = HttpClient();

  String get _base {
    final b = baseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static List<T> _asList<T>(
      dynamic data, T Function(Map<String, dynamic>) fromJson) {
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
    final res = await req.close().timeout(_getTimeout);
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}: $body');
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final req = await _client.postUrl(Uri.parse('$_base$path'));
    if (apiKey != null) req.headers.add('X-API-Key', apiKey!);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close().timeout(_postTimeout);
    final resBody = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: $resBody');
    }
    if (resBody.isEmpty) return null;
    return jsonDecode(resBody);
  }

  Future<dynamic> _put(String path, [Map<String, dynamic>? body]) async {
    final req = await _client.putUrl(Uri.parse('$_base$path'));
    if (apiKey != null) req.headers.add('X-API-Key', apiKey!);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(_postTimeout);
    final resBody = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: $resBody');
    }
    if (resBody.isEmpty) return null;
    return jsonDecode(resBody);
  }

  Future<void> _delete(String path) async {
    final req = await _client.deleteUrl(Uri.parse('$_base$path'));
    if (apiKey != null) req.headers.add('X-API-Key', apiKey!);
    final res = await req.close().timeout(_getTimeout);
    if (res.statusCode >= 400) {
      final body = await res.transform(utf8.decoder).join();
      throw Exception('HTTP ${res.statusCode}: $body');
    }
  }

  // ── Bulk refresh ──────────────────────────────────────────────────────────

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait<void>([
        _fetchDevices(),
        _fetchPackages(),
        _fetchReleases(),
        _fetchTasks(),
        _fetchAlerts(),
        _fetchAlertCount(),
      ]);
    } catch (e) {
      _error = '无法连接 OTA 服务器：$e';
    }
    if (_isDisposed) return;
    _loading = false;
    notifyListeners();
  }

  Future<void> _fetchDevices() async {
    final data = await _get('/devices?limit=200');
    _devices = _asList(data, OtaDevice.fromJson);
  }

  Future<void> _fetchPackages() async {
    final data = await _get('/packages?limit=200');
    _packages = _asList(data, OtaPackage.fromJson);
  }

  Future<void> _fetchReleases() async {
    final data = await _get('/releases?limit=200');
    _releases = _asList(data, OtaRelease.fromJson);
  }

  Future<void> _fetchTasks() async {
    final data = await _get('/tasks?limit=200');
    _tasks = _asList(data, OtaTask.fromJson);
  }

  Future<void> _fetchAlerts() async {
    try {
      final data = await _get('/alerts?limit=100');
      _alerts = _asList(data, OtaAlert.fromJson);
    } catch (_) {
      _alerts = [];
    }
  }

  Future<void> _fetchAlertCount() async {
    try {
      final data = await _get('/alerts/count');
      _alertCount =
          (data as Map)['unacknowledged_count'] as int? ?? 0;
    } catch (_) {
      _alertCount = 0;
    }
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────

  Future<OtaTask?> createTask(String deviceId, int releaseId) async {
    final data = await _post('/tasks/create', {
      'device_id': deviceId,
      'release_id': releaseId,
    });
    if (data == null) return null;
    return OtaTask.fromJson(data as Map<String, dynamic>);
  }

  // ── Releases ──────────────────────────────────────────────────────────────

  Future<void> rollbackRelease(int releaseId, {String reason = ''}) async {
    await _post('/rollback/releases/$releaseId', {
      'reason': reason,
    });
  }

  // ── Alerts ────────────────────────────────────────────────────────────────

  Future<void> ackAlert(int alertId, {String by = 'admin'}) async {
    await _post('/alerts/$alertId/ack', {'acknowledged_by': by});
  }

  // ── Telemetry ─────────────────────────────────────────────────────────────

  Future<OtaDeviceHealth?> fetchDeviceHealth(String deviceId) async {
    final data = await _get('/telemetry/health/$deviceId');
    if (data == null) return null;
    return OtaDeviceHealth.fromJson(data as Map<String, dynamic>);
  }

  Future<List<OtaDeviceHealth>> fetchFleetHealth() async {
    final data = await _get('/telemetry/fleet-health?limit=200');
    return _asList(data, OtaDeviceHealth.fromJson);
  }

  Future<List<OtaTelemetry>> fetchTelemetryHistory(
    String deviceId, {
    int hours = 24,
  }) async {
    final data =
        await _get('/telemetry/history/$deviceId?hours=$hours');
    return _asList(data, OtaTelemetry.fromJson);
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  Future<OtaDiagCommand?> createDiagCommand(
    String deviceId,
    String commandType, {
    Map<String, dynamic>? params,
  }) async {
    final data = await _post('/diagnostics/command', {
      'device_id': deviceId,
      'command_type': commandType,
      if (params != null) 'params': params, // ignore: use_null_aware_elements
    });
    if (data == null) return null;
    return OtaDiagCommand.fromJson(data as Map<String, dynamic>);
  }

  Future<List<OtaDiagCommand>> fetchDiagCommands({
    String? deviceId,
    int limit = 50,
  }) async {
    final q = StringBuffer('/diagnostics/commands?limit=$limit');
    if (deviceId != null) q.write('&device_id=$deviceId');
    final data = await _get(q.toString());
    return _asList(data, OtaDiagCommand.fromJson);
  }

  // ── Config push ───────────────────────────────────────────────────────────

  Future<OtaDeviceConfig?> pushConfig({
    String? deviceId,
    int? groupId,
    required String configKey,
    required Map<String, dynamic> configValue,
    required String version,
  }) async {
    final data = await _post('/config/push', {
      if (deviceId != null) 'device_id': deviceId, // ignore: use_null_aware_elements
      if (groupId != null) 'group_id': groupId, // ignore: use_null_aware_elements
      'config_key': configKey,
      'config_value': configValue,
      'version': version,
    });
    if (data == null) return null;
    return OtaDeviceConfig.fromJson(data as Map<String, dynamic>);
  }

  Future<List<OtaDeviceConfig>> fetchConfigHistory({
    String? deviceId,
    int limit = 50,
  }) async {
    final q = StringBuffer('/config/history?limit=$limit');
    if (deviceId != null) q.write('&device_id=$deviceId');
    final data = await _get(q.toString());
    return _asList(data, OtaDeviceConfig.fromJson);
  }

  // ── Rollback ──────────────────────────────────────────────────────────────

  Future<OtaRollbackCommand?> createRollbackCommand({
    required List<String> deviceIds,
    required String packageName,
    required String targetVersion,
    String reason = '',
    bool force = false,
  }) async {
    final data = await _post('/rollback/commands', {
      'device_ids': deviceIds,
      'package_name': packageName,
      'target_version': targetVersion,
      'reason': reason,
      'force': force,
    });
    if (data == null) return null;
    return OtaRollbackCommand.fromJson(data as Map<String, dynamic>);
  }

  Future<List<OtaRollbackCommand>> fetchRollbackCommands({
    int limit = 50,
  }) async {
    final data = await _get('/rollback/commands?limit=$limit');
    return _asList(data, OtaRollbackCommand.fromJson);
  }

  // ── Devices ───────────────────────────────────────────────────────────────

  Future<void> updateDevice(
    String deviceId, {
    String? channel,
    List<String>? tags,
  }) async {
    await _put('/devices/$deviceId', {
      if (channel != null) 'channel': channel, // ignore: use_null_aware_elements
      if (tags != null) 'tags': tags, // ignore: use_null_aware_elements
    });
  }

  Future<void> deleteDevice(String deviceId) async {
    await _delete('/devices/$deviceId');
  }

  @override
  void dispose() {
    _isDisposed = true;
    _client.close();
    super.dispose();
  }
}
