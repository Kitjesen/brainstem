import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart' hide Duration;

/// Describes a single logged gRPC message.
class ProtocolLogEntry {
  final DateTime time;
  final String direction; // '→' outgoing, '←' incoming
  final String method;
  final String summary;
  ProtocolLogEntry(this.time, this.direction, this.method, this.summary);
}

/// Central gRPC connection manager for the robot.
///
/// Communicates with the han_dog UnifiedCmsServer via gRPC.
/// The server sends individual [SingleJoint] updates per motor;
/// this service aggregates them into a complete [AllJoints] snapshot for the UI.
///
/// Features:
/// - gRPC keepalive for LAN reliability
/// - Auto-reconnect with exponential backoff on stream failures
/// - Connection health monitoring (stale detection, reconnect state)
/// - Proper gRPC error code handling
class GrpcService extends ChangeNotifier {
  ClientChannel? _channel;
  CmsClient? _client;

  String _host = '192.168.66.192';
  int _port = 13145;
  bool _connected = false;
  String? _error;

  /// Callback for UI-level error notifications.
  void Function(String message)? onErrorNotify;

  // Real-time data
  History? _latestHistory;
  Imu? _latestImu;
  AllJoints? _latestJoints;
  Params? _params;
  String _cmsState = '';

  // Profile
  String _currentProfile = '';
  String _currentProfileDescription = '';
  List<String> _availableProfiles = [];
  List<String> _profileDescriptions = [];

  // Joint aggregation from SingleJoint messages
  // The real server sends individual motor reports; we accumulate them here.
  final List<double> _jointPositions = List.filled(16, 0.0);
  final List<double> _jointVelocities = List.filled(16, 0.0);
  final List<double> _jointTorques = List.filled(16, 0.0);
  final List<int> _jointStatuses = List.filled(16, 0);
  DateTime? _lastJointNotify;
  static const _jointThrottleMs = 20; // 50Hz max UI update rate for joints

  // Streams
  StreamSubscription? _stateSub;
  StreamSubscription? _historySub;
  StreamSubscription? _imuSub;
  StreamSubscription? _jointSub;

  // Protocol log
  final List<ProtocolLogEntry> protocolLog = [];
  static const int _maxLogEntries = 500;

  // Torque history (4 legs x 50 points)
  static const int _maxTorqueHist = 50;
  final List<List<double>> torqueHistory = List.generate(4, (_) => []);

  // RTT history (last 120 samples, 1/sec)
  static const int _maxRttHist = 120;
  final List<double> rttHistory = [];
  double _lastRttMs = 0;
  Timer? _rttTimer;

  // Frequency tracking
  int _historyCount = 0;
  int _imuCount = 0;
  int _jointCount = 0;
  DateTime? _freqStart;
  double historyHz = 0;
  double imuHz = 0;
  double jointHz = 0;

  // Uptime
  DateTime? _serverStartTime;
  DateTime? _connectTime;

  // Session statistics
  int _walkCmdCount = 0; // total walk commands sent
  int _walkActiveMs = 0; // accumulated ms while walking
  DateTime? _walkStart; // when current walk segment started
  double _maxTorqueEver = 0; // max single-joint torque seen this session

  // ── Coalesced notifications (max 60Hz) ──
  Timer? _pendingNotify;

  // ── Connection health monitoring ──
  bool _reconnecting = false;
  int _reconnectAttempts = 0;
  DateTime? _lastDataTime;
  Timer? _healthTimer;
  bool _stale = false;
  static const _staleThresholdMs = 5000; // 5 seconds without data → stale

  // ── Auto-reconnect ──
  static const _maxBackoffMs = 30000; // 30 seconds max backoff
  static const _initialBackoffMs = 1000; // 1 second initial backoff
  static const _maxReconnectAttempts = 20; // give up after 20 attempts
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;
  bool _reconnectLimitReached = false;

  // Getters
  String get host => _host;
  int get port => _port;
  bool get connected => _connected;
  String? get error => _error;
  History? get latestHistory => _latestHistory;
  Imu? get latestImu => _latestImu;
  AllJoints? get latestJoints => _latestJoints;
  Params? get params => _params;
  String get cmsState => _cmsState;
  String get currentProfile => _currentProfile;
  String get currentProfileDescription => _currentProfileDescription;
  List<String> get availableProfiles => List.unmodifiable(_availableProfiles);
  List<String> get profileDescriptions =>
      List.unmodifiable(_profileDescriptions);
  bool get hasProfiles => _availableProfiles.isNotEmpty;
  CmsClient? get client => _client;
  DateTime? get serverStartTime => _serverStartTime;
  DateTime? get connectTime => _connectTime;
  int get uptimeSeconds => _connectTime != null
      ? DateTime.now().difference(_connectTime!).inSeconds
      : 0;

  // Session statistics getters
  int get walkCmdCount => _walkCmdCount;
  int get _walkElapsedMs => _walkStart != null
      ? DateTime.now().difference(_walkStart!).inMilliseconds
      : 0;
  int get walkActiveMs => _walkActiveMs + _walkElapsedMs;
  double get maxTorqueEver => _maxTorqueEver;

  // Health getters
  bool get isReconnecting => _reconnecting;
  int get reconnectAttempts => _reconnectAttempts;
  DateTime? get lastDataTime => _lastDataTime;
  bool get isStale => _stale;
  bool get reconnectLimitReached => _reconnectLimitReached;
  double get lastRttMs => _lastRttMs;

  /// Overall health status string for the UI.
  String get healthStatus {
    if (_reconnectLimitReached) return '重连失败（已达上限 $_maxReconnectAttempts 次）';
    if (!_connected && !_reconnecting) return '已断开';
    if (_reconnecting) return '重连中 (#$_reconnectAttempts)...';
    if (_stale) return '无数据';
    return '正常';
  }

  /// Connection quality grade: A / B / C / D / F
  /// Based on: avg RTT, stale events, reconnect count.
  String get qualityGrade {
    if (!_connected) return 'F';
    if (_stale) return 'D';
    if (rttHistory.isEmpty) return '—';
    var sum = 0.0, max = 0.0;
    for (final v in rttHistory) {
      sum += v;
      if (v > max) max = v;
    }
    final avg = sum / rttHistory.length;
    // Penalty for reconnects this session
    final penalty = _reconnectAttempts * 5.0;
    final score = (avg + max / 3 + penalty).clamp(0.0, 200.0);
    if (score < 15) return 'A';
    if (score < 30) return 'B';
    if (score < 60) return 'C';
    if (score < 100) return 'D';
    return 'F';
  }

  static const _gradeDesc = {
    'A': '极佳',
    'B': '良好',
    'C': '一般',
    'D': '较差',
    'F': '不可用',
  };

  /// Quality grade description
  String get qualityDescription => _gradeDesc[qualityGrade] ?? '--';

  /// 合并 16ms 内的多次数据更新为单次 [notifyListeners()]，避免过度重建。
  /// 仅用于高频数据流回调；连接状态变更应直接调用 [notifyListeners()]。
  void _scheduleNotify() {
    if (_pendingNotify != null) return;
    _pendingNotify = Timer(const Duration(milliseconds: 16), () {
      _pendingNotify = null;
      notifyListeners();
    });
  }

  void _log(String direction, String method, [String summary = '']) {
    protocolLog.insert(
      0,
      ProtocolLogEntry(DateTime.now(), direction, method, summary),
    );
    if (protocolLog.length > _maxLogEntries) {
      protocolLog.removeLast();
    }
  }

  void _updateFrequency() {
    final now = DateTime.now();
    if (_freqStart == null) {
      _freqStart = now;
      return;
    }
    final elapsed = now.difference(_freqStart!).inMilliseconds / 1000.0;
    if (elapsed >= 1.0) {
      historyHz = _historyCount / elapsed;
      imuHz = _imuCount / elapsed;
      jointHz = _jointCount / elapsed;
      _historyCount = 0;
      _imuCount = 0;
      _jointCount = 0;
      _freqStart = now;
    }
  }

  /// Mark that data was received — used by health monitoring.
  void _touchData() {
    _lastDataTime = DateTime.now();
    if (_stale) {
      _stale = false;
      // Stale flag cleared — will notify via the next data callback
    }
  }

  /// Start periodic health check timer.
  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_connected) return;
      final now = DateTime.now();
      if (_lastDataTime != null &&
          now.difference(_lastDataTime!).inMilliseconds > _staleThresholdMs) {
        if (!_stale) {
          _stale = true;
          _log('⚠', 'Health', '超过 5s 未收到数据，连接可能已中断');
          notifyListeners();
        }
      }
    });
  }

  Future<void> connect(String host, int port) async {
    _intentionalDisconnect = false;
    disconnect();
    _intentionalDisconnect = false; // reset after disconnect sets it
    _host = host;
    _port = port;
    _error = null;

    try {
      _channel = ClientChannel(
        host,
        port: port,
        options: ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          connectTimeout: const Duration(seconds: 10),
          idleTimeout: const Duration(minutes: 5),
          // gRPC keepalive for LAN reliability
          keepAlive: const ClientKeepAliveOptions(
            pingInterval: Duration(seconds: 10),
            timeout: Duration(seconds: 5),
            permitWithoutCalls: true,
          ),
        ),
      );
      _client = CmsClient(_channel!);

      // Test connection by getting start time
      _log('→', 'GetStartTime');
      final ts = await _client!.getStartTime(Empty());
      _serverStartTime = DateTime.fromMillisecondsSinceEpoch(
        ts.seconds.toInt() * 1000,
      );
      _connectTime = DateTime.now();
      _log('←', 'GetStartTime', 'OK');

      _connected = true;
      _reconnecting = false;
      _reconnectAttempts = 0;
      _touchData();
      notifyListeners();

      // Persist last connected host/port for next session
      _saveLastConnected(host, port);

      // Start health monitoring and RTT measurement
      _startHealthMonitor();
      _startRttTimer();

      // Fetch params and profile info
      _fetchParams();
      _fetchProfile();
      _fetchCmsState();

      // Start streaming
      _startStreams();
    } catch (e) {
      _error = e.toString();
      _connected = false;
      _log('✕', 'Connect', _error!);
      onErrorNotify?.call('连接失败: $_error');
      notifyListeners();
    }
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pendingNotify?.cancel();
    _pendingNotify = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _rttTimer?.cancel();
    _rttTimer = null;
    _teardownConnection();
    _connected = false;
    _reconnecting = false;
    _reconnectAttempts = 0;
    _reconnectLimitReached = false;
    _stale = false;
    _latestHistory = null;
    _latestImu = null;
    _latestJoints = null;
    _freqStart = null;
    _serverStartTime = null;
    _connectTime = null;
    _lastJointNotify = null;
    _lastDataTime = null;
    historyHz = 0;
    imuHz = 0;
    jointHz = 0;
    _currentProfile = '';
    _currentProfileDescription = '';
    _availableProfiles = [];
    _profileDescriptions = [];
    _cmsState = '';
    // Reset session statistics
    _walkCmdCount = 0;
    _walkActiveMs = 0;
    _walkStart = null;
    _maxTorqueEver = 0;
    _resetJointArrays();
    // Reset RTT and torque history so qualityGrade starts fresh on next connection
    rttHistory.clear();
    _lastRttMs = 0;
    for (final leg in torqueHistory) {
      leg.clear();
    }
    notifyListeners();
  }

  // ── Auto-Reconnect ──

  /// Attempt to reconnect after a stream failure.
  /// Uses exponential backoff: 1s, 2s, 4s, 8s, ... up to 30s.
  /// Stops automatically after [_maxReconnectAttempts] consecutive failures.
  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnecting) return; // already scheduled

    _reconnectAttempts++;

    if (_reconnectAttempts > _maxReconnectAttempts) {
      _reconnectLimitReached = true;
      _reconnecting = false;
      _log(
        '⛔',
        'Reconnect',
        'max attempts ($_maxReconnectAttempts) reached — stopping auto-reconnect',
      );
      onErrorNotify?.call('自动重连已达上限（$_maxReconnectAttempts 次），请手动重新连接');
      notifyListeners();
      return;
    }

    _reconnecting = true;

    final delayMs = _calcBackoff(_reconnectAttempts);
    _log('⟳', 'Reconnect', 'attempt #$_reconnectAttempts in ${delayMs}ms');
    notifyListeners();

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _performReconnect();
    });
  }

  /// 将 16 路关节本地数组归零（断连 / 初始化时调用）。
  void _resetJointArrays() {
    _jointPositions.fillRange(0, 16, 0.0);
    _jointVelocities.fillRange(0, 16, 0.0);
    _jointTorques.fillRange(0, 16, 0.0);
    _jointStatuses.fillRange(0, 16, 0);
  }

  /// 计算第 [attempt] 次重连的等待毫秒数（指数退避 + ±20% jitter）。
  int _calcBackoff(int attempt) {
    final base = math.min(
      _initialBackoffMs * math.pow(2, attempt - 1).toInt(),
      _maxBackoffMs,
    );
    final jitter = (base * 0.2 * (math.Random().nextDouble() * 2 - 1)).toInt();
    return base + jitter;
  }

  /// 取消流订阅并关闭 channel/client（不重置重连状态）。
  void _teardownConnection() {
    _stateSub?.cancel();
    _historySub?.cancel();
    _imuSub?.cancel();
    _jointSub?.cancel();
    _stateSub = null;
    _historySub = null;
    _imuSub = null;
    _jointSub = null;
    _channel?.shutdown();
    _channel = null;
    _client = null;
  }

  Future<void> _performReconnect() async {
    if (_intentionalDisconnect) return;

    _log('⟳', 'Reconnect', 'attempting reconnection...');

    // Clean up old resources without resetting reconnect state
    _teardownConnection();

    try {
      _channel = ClientChannel(
        _host,
        port: _port,
        options: ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          connectTimeout: const Duration(seconds: 10),
          idleTimeout: const Duration(minutes: 5),
          keepAlive: const ClientKeepAliveOptions(
            pingInterval: Duration(seconds: 10),
            timeout: Duration(seconds: 5),
            permitWithoutCalls: true,
          ),
        ),
      );
      _client = CmsClient(_channel!);

      // Verify connection
      final ts = await _client!.getStartTime(Empty());
      _serverStartTime = DateTime.fromMillisecondsSinceEpoch(
        ts.seconds.toInt() * 1000,
      );

      _connected = true;
      _reconnecting = false;
      _reconnectAttempts = 0;
      _stale = false;
      _touchData();
      _log('✓', 'Reconnect', 'success');
      notifyListeners();

      // Restart streams
      _startStreams();
      _fetchParams();
      _fetchProfile();
      _fetchCmsState();
    } catch (e) {
      _log('✕', 'Reconnect', 'failed: $e');
      _connected = false;
      // Schedule another attempt
      _reconnecting = false; // allow _scheduleReconnect to fire
      _scheduleReconnect();
    }
  }

  /// 将 ProfileInfo 响应写入本地字段并触发 notifyListeners。
  void _applyProfileInfo(ProfileInfo info) {
    _currentProfile = info.current;
    _currentProfileDescription = info.currentDescription;
    _availableProfiles = List<String>.from(info.available);
    _profileDescriptions = List<String>.from(info.descriptions);
    notifyListeners();
  }

  void _applyCmsState(CmsState state) {
    _cmsState = switch (state.kind) {
      CmsStateKind.CMS_STATE_KIND_ZERO => 'Zero',
      CmsStateKind.CMS_STATE_KIND_GROUNDED => 'Grounded',
      CmsStateKind.CMS_STATE_KIND_STANDING => 'Standing',
      CmsStateKind.CMS_STATE_KIND_WALKING => 'Walking',
      CmsStateKind.CMS_STATE_KIND_TRANSITIONING => switch (state.transition) {
        CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP => 'StandUp',
        CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN => 'SitDown',
        CmsTransitionKind.CMS_TRANSITION_KIND_GESTURE => 'Gesture',
        _ => 'Transitioning',
      },
      _ => 'Unknown',
    };
  }

  Future<void> _fetchCmsState() async {
    if (_client == null) return;
    try {
      _log('→', 'GetCmsState');
      final state = await _client!.getCmsState(Empty());
      _applyCmsState(state);
      _log('←', 'GetCmsState', _cmsState);
      notifyListeners();
    } catch (e) {
      _log('✕', 'GetCmsState', e.toString());
    }
  }

  Future<void> _fetchProfile() async {
    if (_client == null) return;
    try {
      _log('→', 'GetProfile');
      final info = await _client!.getProfile(Empty());
      _applyProfileInfo(info);
      _log(
        '←',
        'GetProfile',
        'current=${info.current}, ${info.available.length}个策略',
      );
    } catch (e) {
      _log('✕', 'GetProfile', e.toString());
      // 非致命错误，服务端可能未配置策略
    }
  }

  Future<bool> switchProfile(String name) async {
    if (_client == null) return false;
    try {
      _log('→', 'SwitchProfile', name);
      final info = await _client!.switchProfile(ProfileRequest(name: name));
      _applyProfileInfo(info);
      _log('←', 'SwitchProfile', '已切换至 ${info.current}');
      return true;
    } catch (e) {
      _log('✕', 'SwitchProfile', e.toString());
      onErrorNotify?.call('切换策略失败: ${_formatGrpcError(e)}');
      return false;
    }
  }

  Future<void> _fetchParams() async {
    if (_client == null) return;
    try {
      _log('→', 'GetParams');
      _params = await _client!.getParams(Empty());
      final robotInfo = _params != null && _params!.hasRobot()
          ? 'robot: ${_params!.robot.type.name}'
          : 'robot: (empty)';
      _log('←', 'GetParams', robotInfo);
      notifyListeners();
    } catch (e) {
      _log('✕', 'GetParams', e.toString());
    }
  }

  void _startStreams() {
    if (_client == null) return;

    // CMS state stream
    _stateSub = _client!
        .listenCmsState(Empty())
        .listen(
          (state) {
            _applyCmsState(state);
            _touchData();
            _scheduleNotify();
          },
          onError: (Object e, StackTrace st) {
            _log('✕', 'ListenCmsState', e.toString());
            _handleStreamError('CmsState', e);
          },
          onDone: () {
            _log('◼', 'ListenCmsState', '服务端关闭了 CmsState 流');
            _handleStreamDone('CmsState');
          },
        );

    // History stream
    _historySub = _client!
        .listenHistory(Empty())
        .listen(
          (history) {
            _latestHistory = history;
            _historyCount++;
            _updateFrequency();
            _touchData();
            _scheduleNotify();
          },
          onError: (Object e, StackTrace st) {
            _log('✕', 'ListenHistory', e.toString());
            _handleStreamError('History', e);
          },
          onDone: () {
            _log('⚠', 'ListenHistory', '服务端关闭了 History 流');
            _handleStreamDone('History');
          },
        );

    // IMU stream
    _imuSub = _client!
        .listenImu(Empty())
        .listen(
          (imu) {
            _latestImu = imu;
            _imuCount++;
            _updateFrequency();
            _touchData();
            _scheduleNotify();
          },
          onError: (Object e, StackTrace st) {
            _log('✕', 'ListenImu', e.toString());
            _handleStreamError('IMU', e);
          },
          onDone: () {
            _log('⚠', 'ListenImu', '服务端关闭了 IMU 流');
            _handleStreamDone('IMU');
          },
        );

    // Joint stream — handles both SingleJoint and AllJoints
    // UnifiedCmsServer sends individual SingleJoint per motor report in hardware mode,
    // or AllJoints batches in simulation mode.
    _jointSub = _client!
        .listenJoint(Empty())
        .listen(
          (joint) {
            _jointCount++;
            _updateFrequency();
            _touchData();

            if (joint.hasSingleJoint()) {
              _handleSingleJoint(joint.singleJoint);
            } else if (joint.hasAllJoints()) {
              _handleAllJoints(joint.allJoints);
            }
          },
          onError: (Object e, StackTrace st) {
            _log('✕', 'ListenJoint', e.toString());
            _handleStreamError('Joint', e);
          },
          onDone: () {
            _log('⚠', 'ListenJoint', '服务端关闭了 Joint 流');
            _handleStreamDone('Joint');
          },
        );
  }

  /// Common reconnect trigger: guard intentional disconnect, then schedule.
  void _triggerReconnect() {
    if (_intentionalDisconnect) return;
    if (_connected) {
      _connected = false;
      _scheduleReconnect();
    }
  }

  /// Handle stream error — trigger auto-reconnect if still supposed to be connected.
  void _handleStreamError(String streamName, dynamic error) {
    if (!_intentionalDisconnect) onErrorNotify?.call('$streamName 流异常: $error');
    _triggerReconnect();
  }

  /// Handle stream done (server closed) — trigger auto-reconnect.
  void _handleStreamDone(String streamName) => _triggerReconnect();

  /// Handle individual motor report from real hardware.
  /// Aggregates into local arrays and periodically builds AllJoints for UI.
  void _handleSingleJoint(SingleJoint sj) {
    final id = sj.id;
    if (id < 0 || id >= 16) return; // 忽略越界 ID
    _jointPositions[id] = sj.position;
    _jointVelocities[id] = sj.velocity;
    _jointTorques[id] = sj.torque;
    _jointStatuses[id] = sj.status;

    // Throttle UI updates: build AllJoints and notify at most every _jointThrottleMs
    final now = DateTime.now();
    if (_lastJointNotify == null ||
        now.difference(_lastJointNotify!).inMilliseconds >= _jointThrottleMs) {
      _lastJointNotify = now;
      _rebuildAllJoints();
      _updateTorqueHistory(_latestJoints!);
      _scheduleNotify();
    }
  }

  /// Handle batched AllJoints from simulation server.
  void _handleAllJoints(AllJoints allJoints) {
    _latestJoints = allJoints;

    // Sync local arrays for consistency (guard against empty payload)
    final pos = allJoints.position.values;
    final vel = allJoints.velocity.values;
    final trq = allJoints.torque.values;
    for (int i = 0; i < 16 && i < pos.length; i++) {
      _jointPositions[i] = pos[i];
    }
    for (int i = 0; i < 16 && i < vel.length; i++) {
      _jointVelocities[i] = vel[i];
    }
    for (int i = 0; i < 16 && i < trq.length; i++) {
      _jointTorques[i] = trq[i];
    }

    _updateTorqueHistory(allJoints);
    _scheduleNotify();
  }

  /// Build an AllJoints protobuf message from the aggregated local arrays.
  void _rebuildAllJoints() {
    _latestJoints = AllJoints(
      position: Matrix4(values: List<double>.from(_jointPositions)),
      velocity: Matrix4(values: List<double>.from(_jointVelocities)),
      torque: Matrix4(values: List<double>.from(_jointTorques)),
      status: Matrix4Int32(values: List<int>.from(_jointStatuses)),
    );
  }

  void _updateTorqueHistory(AllJoints joints) {
    if (joints.torque.values.length < 12) return;
    for (int leg = 0; leg < 4; leg++) {
      final base = leg * 3;
      final avg =
          (joints.torque.values[base].abs() +
              joints.torque.values[base + 1].abs() +
              joints.torque.values[base + 2].abs()) /
          3;
      torqueHistory[leg].add(avg);
      if (torqueHistory[leg].length > _maxTorqueHist) {
        torqueHistory[leg].removeAt(0);
      }
    }
    // Track peak torque for session statistics
    for (final t in joints.torque.values) {
      if (t.abs() > _maxTorqueEver) _maxTorqueEver = t.abs();
    }
  }

  // --- Commands ---
  // All motion commands use proper GrpcError.code checks instead of string matching.

  Future<void> enable() async {
    if (_client == null) return;
    try {
      _log('→', 'Enable');
      await _client!.enable(Empty());
      _log('←', 'Enable', 'OK');
    } catch (e) {
      _log('✕', 'Enable', e.toString());
      onErrorNotify?.call('Enable 失败: ${_formatGrpcError(e)}');
    }
  }

  Future<void> disable() async {
    if (_client == null) return;
    try {
      _log('→', 'Disable');
      await _client!.disable(Empty());
      _log('←', 'Disable', 'OK');
    } catch (e) {
      _log('✕', 'Disable', e.toString());
      onErrorNotify?.call('Disable 失败: ${_formatGrpcError(e)}');
    }
  }

  Future<void> standUp() async {
    if (_client == null) return;
    try {
      _log('→', 'StandUp');
      await _client!.standUp(Empty());
      _log('←', 'StandUp', 'OK');
    } catch (e) {
      _log('✕', 'StandUp', e.toString());
      onErrorNotify?.call('StandUp 失败: ${_formatGrpcError(e)}');
    }
  }

  Future<void> sitDown() async {
    if (_client == null) return;
    try {
      _log('→', 'SitDown');
      await _client!.sitDown(Empty());
      _log('←', 'SitDown', 'OK');
    } catch (e) {
      _log('✕', 'SitDown', e.toString());
      onErrorNotify?.call('SitDown 失败: ${_formatGrpcError(e)}');
    }
  }

  Future<void> walk(double x, double y, double z) async {
    if (_client == null) return;
    try {
      final v = Vector3(x: x, y: y, z: z);
      await _client!.walk(v);
      // Track walk statistics
      final isMoving = x != 0 || y != 0 || z != 0;
      if (isMoving) {
        _walkCmdCount++;
        _walkStart ??= DateTime.now();
      } else if (_walkStart != null) {
        _walkActiveMs += DateTime.now().difference(_walkStart!).inMilliseconds;
        _walkStart = null;
      }
    } catch (e) {
      // Walk commands are sent at high frequency; avoid toast spam and keep logs concise.
      if (_isFailedPrecondition(e)) {
        _log('✕', 'Walk', _formatGrpcError(e));
      }
    }
  }

  // ── RTT measurement ──

  void _startRttTimer() {
    _rttTimer?.cancel();
    _rttTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _measureRtt(),
    );
  }

  Future<void> _measureRtt() async {
    if (_client == null || !_connected) return;
    final sw = Stopwatch()..start();
    try {
      await _client!.getStartTime(
        Empty(),
        options: CallOptions(timeout: const Duration(seconds: 2)),
      );
      sw.stop();
      _lastRttMs = sw.elapsedMilliseconds.toDouble();
      rttHistory.add(_lastRttMs);
      if (rttHistory.length > _maxRttHist) rttHistory.removeAt(0);
      _scheduleNotify();
    } catch (_) {}
  }

  // ── Last-connected persistence ──

  static File _lastConnectedFile() {
    final String dir;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      dir = '$appData\\sirius';
    } else {
      dir = '${Platform.environment['HOME']}/.sirius';
    }
    return File('$dir${Platform.pathSeparator}last_connected.json');
  }

  static Future<void> _saveLastConnected(String host, int port) async {
    try {
      final f = _lastConnectedFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'host': host, 'port': port}));
    } catch (_) {}
  }

  /// Returns the last successfully connected {host, port}, or null if none.
  static Future<({String host, int port})?> loadLastConnected() async {
    try {
      final f = _lastConnectedFile();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (host: data['host'] as String, port: data['port'] as int);
    } catch (_) {
      return null;
    }
  }

  // ── gRPC error helpers ──

  /// Check if error is a gRPC FAILED_PRECONDITION (ControlArbiter rejection).
  bool _isFailedPrecondition(dynamic e) {
    if (e is GrpcError) {
      return e.code == StatusCode.failedPrecondition;
    }
    return false;
  }

  /// Format a gRPC error for display.
  String _formatGrpcError(dynamic e) {
    if (e is GrpcError) {
      return e.message ?? 'gRPC error (code ${e.code})';
    }
    return e.toString();
  }

  @override
  void dispose() {
    // 设置标志后再 disconnect，确保不触发重连逻辑
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _healthTimer?.cancel();
    _pendingNotify?.cancel();
    disconnect(); // 内部调用 _teardownConnection() + 状态重置 + notifyListeners
    super.dispose();
  }
}
