import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:vector_math/vector_math.dart';

import 'gamepad.dart';
import 'web_zero_stability.dart' show ZeroNotStarted;

/// Browser input uses the same Gamepad/RealControlDog path as the radio handset.
class WebController implements Gamepad, HardStopGamepad, InputHealthGamepad {
  final String _token;
  final String assetsPath;
  final Map<String, Object?> Function() _readStatus;
  final Future<void> Function(String slot) _selectSlot;
  final Future<Map<String, Object?>> Function() _zeroAll;
  final Duration inputTimeout;
  final Duration watchdogInterval;
  final Stopwatch _clock = Stopwatch()..start();
  final _random = Random.secure();
  final _sessions = <String, int>{};
  final _directions = StreamController<Vector3>.broadcast(sync: true);
  final _stand = StreamController<bool>.broadcast(sync: true);
  final _sit = StreamController<bool>.broadcast(sync: true);
  final _idle = StreamController<bool>.broadcast(sync: true);
  final _enabled = StreamController<bool>.broadcast(sync: true);
  final _red = StreamController<bool>.broadcast(sync: true);
  final _calibrate = StreamController<void>.broadcast(sync: true);
  final _switch = StreamController<void>.broadcast(sync: true);
  final _hardStops = StreamController<void>.broadcast(sync: true);
  HttpServer? _server;
  WebSocket? _socket;
  String? _ownerSession;
  Timer? _watchdog;
  Timer? _statusTimer;
  int? _lastInputMs;
  var _sequence = -1;
  var _intent = false;
  var _paused = true;
  var _needNeutral = true;
  var _busy = false;
  var _zeroFailed = false;
  var _disposed = false;
  var _inputFrames = 0;
  var _hz = 0;
  var _hzStarted = 0;
  var _raw = Vector3.zero();

  WebController({
    required String token,
    required this.assetsPath,
    required Map<String, Object?> Function() status,
    required Future<void> Function(String slot) selectSlot,
    required Future<Map<String, Object?>> Function() zeroAll,
    this.inputTimeout = const Duration(milliseconds: 150),
    this.watchdogInterval = const Duration(milliseconds: 25),
  }) : _token = token,
       _readStatus = status,
       _selectSlot = selectSlot,
       _zeroAll = zeroAll {
    if (token.trim().length < 24 || token != token.trim()) {
      throw ArgumentError(
        'Web control token must contain at least 24 characters',
      );
    }
    if (inputTimeout <= Duration.zero || watchdogInterval <= Duration.zero) {
      throw ArgumentError('Invalid watchdog timing');
    }
  }

  int get boundPort => _server?.port ?? 0;
  @override
  Stream<Vector3> get direction => _directions.stream;
  @override
  Stream<bool> get standup => _stand.stream;
  @override
  Stream<bool> get sitdown => _sit.stream;
  @override
  Stream<bool> get idle => _idle.stream;
  @override
  Stream<bool> get enabled => _enabled.stream;
  @override
  Stream<bool> get red => _red.stream;
  @override
  Stream<void> get calibrate => _calibrate.stream;
  @override
  Stream<void> get switchProfile => _switch.stream;
  @override
  Stream<void> get hardStop => _hardStops.stream;
  @override
  bool get inputHealthy =>
      !_disposed &&
      _socket != null &&
      _lastInputMs != null &&
      _clock.elapsedMilliseconds - _lastInputMs! < inputTimeout.inMilliseconds;
  @override
  bool get hardStopActive => _paused || !inputHealthy;
  @override
  int get inputHz => inputHealthy ? _hz : 0;

  Future<void> start({String host = '127.0.0.1', int port = 0}) async {
    if (_server != null || _disposed) {
      throw StateError('Already opened/disposed');
    }
    for (final name in ['index.html', 'app.js', 'styles.css']) {
      if (!File('$assetsPath/$name').existsSync()) {
        throw StateError('Missing web asset: $name');
      }
    }
    _server = await HttpServer.bind(host, port);
    _server!.listen((request) {
      _handleHttp(request).catchError((Object error, StackTrace stack) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.close();
        } catch (_) {}
      });
    });
    _watchdog = Timer.periodic(watchdogInterval, (_) {
      if (!inputHealthy && !_paused) _pause();
      final now = _clock.elapsedMilliseconds;
      if (_ownerSession != null && (_sessions[_ownerSession] ?? -1) <= now) {
        _pause();
        unawaited(
          _socket?.close(WebSocketStatus.policyViolation, 'Session expired'),
        );
      }
      if (now - _hzStarted >= 1000) {
        _hz = (_inputFrames * 1000 / (now - _hzStarted)).round();
        _hzStarted = now;
        _inputFrames = 0;
      }
    });
    _statusTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sendStatus();
    });
  }

  Map<String, Object?> _snapshot() {
    Map<String, Object?> data;
    try {
      data = Map.of(_readStatus());
    } catch (_) {
      data = {
        'ready': false,
        'hardware_state_unknown': true,
        'block_reason': '无法读取控制状态',
      };
    }
    return {
      ...data,
      if (_zeroFailed) ...{
        'can_enable': false,
        'can_zero': false,
        'can_open_zero': false,
        'can_switch': false,
        'zero_phase': 'uncertain',
        'zero_block_reason': '标零写入结果未确认，请检查机械零位和反馈后重新启动控制程序；不要重复标零',
        'block_reason': '标零结果未确认，检查机械位置后重新启动控制程序',
      },
      'type': 'status',
      'connected': _socket != null,
      'input_healthy': inputHealthy,
      'armed':
          _intent &&
          !hardStopActive &&
          data['motor_enabled'] == true &&
          data['motor_output_enabled'] != false,
      'control_paused': _paused,
      'busy': _busy || data['busy'] == true,
      'input_timeout_ms': inputTimeout.inMilliseconds,
    };
  }

  void _sendStatus() => _send(_snapshot());
  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket?.readyState == WebSocket.open) {
      try {
        socket!.add(jsonEncode(message));
      } catch (_) {
        _pause();
      }
    }
  }

  void _pause() {
    final notify = !_paused;
    _paused = true;
    _intent = false;
    _needNeutral = true;
    _raw = Vector3.zero();
    // Lost Wi-Fi must stop motion, not drop a standing robot's support torque.
    if (notify && !_disposed) _hardStops.add(null);
    if (!_disposed) _directions.add(Vector3.zero());
  }

  bool _sameOrigin(HttpRequest request) {
    final raw = request.headers.value('origin');
    final origin = raw == null ? null : Uri.tryParse(raw);
    final target = request.requestedUri;
    return origin != null &&
        origin.userInfo.isEmpty &&
        !origin.hasQuery &&
        !origin.hasFragment &&
        (origin.path.isEmpty || origin.path == '/') &&
        origin.scheme == target.scheme &&
        origin.host == target.host &&
        origin.port == target.port;
  }

  String? _session(HttpRequest request) {
    for (final cookie in request.cookies) {
      if (cookie.name == 'thunder_session' &&
          (_sessions[cookie.value] ?? -1) > _clock.elapsedMilliseconds) {
        return cookie.value;
      }
    }
    return null;
  }

  Future<void> _json(HttpRequest request, int code, Object value) async {
    request.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(value));
    await request.response.close();
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const FormatException('Expected application/json');
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > 4096) {
        throw const FormatException('Request too large');
      }
      bytes.addAll(chunk);
    }
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map<String, dynamic>) throw const FormatException('Bad body');
    return body;
  }

  bool _tokenMatches(String candidate) {
    final a = utf8.encode(candidate);
    final b = utf8.encode(_token);
    var different = a.length ^ b.length;
    for (var i = 0; i < b.length; i++) {
      different |= b[i] ^ (i < a.length ? a[i] : 0);
    }
    return different == 0;
  }

  Future<void> _handleHttp(HttpRequest request) async {
    request.response.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'",
      );
    final path = request.uri.path;
    if (path == '/api/session' && request.method == 'POST') {
      if (!_sameOrigin(request)) {
        return _json(request, 403, {'error': 'Origin rejected'});
      }
      try {
        final body = await _body(request);
        final token = body['token'];
        if (token is! String || !_tokenMatches(token)) {
          return _json(request, 401, {'error': '控制口令不正确'});
        }
        _sessions.removeWhere(
          (_, expiry) => expiry <= _clock.elapsedMilliseconds,
        );
        if (_sessions.length >= 16) {
          final removable = _sessions.keys.firstWhere(
            (key) => key != _ownerSession,
          );
          _sessions.remove(removable);
        }
        final sid = base64Url.encode(
          List.generate(32, (_) => _random.nextInt(256)),
        );
        _sessions[sid] =
            _clock.elapsedMilliseconds +
            const Duration(hours: 12).inMilliseconds;
        request.response.cookies.add(
          Cookie('thunder_session', sid)
            ..httpOnly = true
            ..sameSite = SameSite.strict
            ..secure = request.requestedUri.scheme == 'https'
            ..path = '/'
            ..maxAge = const Duration(hours: 12).inSeconds,
        );
        return _json(request, 200, {'ok': true});
      } on FormatException {
        return _json(request, 400, {'error': '请求格式错误'});
      }
    }
    if (path == '/api/status' && request.method == 'GET') {
      if (_session(request) == null) {
        return _json(request, 401, {'error': '需要登录'});
      }
      return _json(request, 200, _snapshot());
    }
    if (path == '/api/logout' && request.method == 'POST') {
      if (!_sameOrigin(request)) {
        return _json(request, 403, {'error': 'Origin rejected'});
      }
      final sid = _session(request);
      if (sid != null) {
        _sessions.remove(sid);
        if (sid == _ownerSession) {
          _pause();
          await _socket?.close(WebSocketStatus.normalClosure);
        }
      }
      request.response.cookies.add(
        Cookie('thunder_session', '')
          ..httpOnly = true
          ..sameSite = SameSite.strict
          ..path = '/'
          ..maxAge = 0,
      );
      return _json(request, 200, {'ok': true});
    }
    if (path == '/ws' && request.method == 'GET') {
      final sid = _session(request);
      if (!_sameOrigin(request) || sid == null) {
        return _json(request, 403, {'error': '未认证或来源不匹配'});
      }
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        return _json(request, 400, {'error': 'WebSocket required'});
      }
      if (_socket != null) {
        if (inputHealthy) return _json(request, 409, {'error': '已有控制端连接'});
        final previous = _socket;
        _pause();
        _socket = null;
        await previous!.close(
          WebSocketStatus.goingAway,
          'Stale control connection',
        );
      }
      final socket = await WebSocketTransformer.upgrade(request);
      if (_disposed || _socket != null) {
        await socket.close(
          WebSocketStatus.policyViolation,
          'Controller occupied',
        );
        return;
      }
      _socket = socket;
      _ownerSession = sid;
      _lastInputMs = null;
      _sequence = -1;
      _pause();
      _sendStatus();
      socket.listen(
        (message) => _handleMessage(socket, message),
        onError: (Object error) => _disconnect(socket),
        onDone: () => _disconnect(socket),
      );
      return;
    }
    if (request.method != 'GET') {
      return _json(request, 405, {'error': 'Method not allowed'});
    }
    final relative = path == '/' ? 'index.html' : path.substring(1);
    if (!{
          'index.html',
          'app.js',
          'styles.css',
          'robot.png',
        }.contains(relative) &&
        !RegExp(r'^icons/[a-z0-9-]+\.svg$').hasMatch(relative)) {
      return _json(request, 404, {'error': 'Not found'});
    }
    final file = File('$assetsPath/$relative');
    if (!file.existsSync()) return _json(request, 404, {'error': 'Not found'});
    final directory = Directory(assetsPath).resolveSymbolicLinksSync();
    if (!file.resolveSymbolicLinksSync().startsWith(
      '$directory${Platform.pathSeparator}',
    )) {
      return _json(request, 403, {'error': 'Not allowed'});
    }
    request.response.headers.contentType = switch (relative.split('.').last) {
      'html' => ContentType.html,
      'js' => ContentType('application', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'svg' => ContentType('image', 'svg+xml'),
      _ => ContentType('image', 'png'),
    };
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  void _disconnect(WebSocket socket) {
    if (!identical(_socket, socket)) return;
    _pause();
    _socket = null;
    _ownerSession = null;
    _lastInputMs = null;
  }

  Future<void> _handleMessage(WebSocket socket, dynamic message) async {
    if (!identical(socket, _socket) || _disposed) return;
    String? id;
    try {
      if (message is! String || utf8.encode(message).length > 4096) {
        throw const FormatException('Invalid message');
      }
      final body = jsonDecode(message);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Invalid message');
      }
      id = body['id'] is String ? body['id'] as String : null;
      final sequence = body['seq'];
      if (sequence is! int ||
          sequence <= _sequence ||
          sequence > 9007199254740991) {
        throw const FormatException('过期或重复的指令');
      }
      _sequence = sequence;
      if (body['type'] == 'input') {
        final axes = body['axes'];
        if (axes is! List ||
            axes.length != 3 ||
            axes.any((v) => v is! num || !v.isFinite || v.abs() > 1)) {
          throw const FormatException('无效的摇杆数值');
        }
        // A late frame must not erase a timeout before the timer gets CPU time.
        if (_lastInputMs != null && !inputHealthy) _pause();
        _lastInputMs = _clock.elapsedMilliseconds;
        _inputFrames++;
        _raw = Vector3(
          (axes[0] as num).toDouble(),
          (axes[1] as num).toDouble(),
          (axes[2] as num).toDouble(),
        );
        final zero = _raw.x == 0 && _raw.y == 0 && _raw.z == 0;
        if (zero) _needNeutral = false;
        final state = _snapshot();
        if (!zero &&
            (_busy ||
                state['busy'] == true ||
                (state['cms'] != 'STANDING' && state['cms'] != 'WALKING'))) {
          _needNeutral = true;
        }
        final canMove =
            state['armed'] == true &&
            !_needNeutral &&
            !_busy &&
            state['ready'] == true &&
            state['motor_enabled'] == true &&
            (state['cms'] == 'STANDING' || state['cms'] == 'WALKING');
        _directions.add(canMove ? Vector3.copy(_raw) : Vector3.zero());
        return;
      }
      if (body['type'] != 'command' || id == null || id.length > 64) {
        throw const FormatException('Invalid command envelope');
      }
      final command = body['command'];
      if (command is! String) throw const FormatException('Missing command');
      final state = _snapshot();
      if (state['ready'] != true && command != 'disable' && command != 'stop') {
        throw StateError('控制程序尚未就绪');
      }
      if ((_busy || state['busy'] == true) &&
          command != 'disable' &&
          command != 'stop') {
        throw StateError('上一项操作尚未完成');
      }
      if (command == 'disable') {
        _pause();
        _enabled.add(false);
      } else if (command == 'stop') {
        _raw = Vector3.zero();
        _needNeutral = true;
        _directions.add(Vector3.zero());
      } else {
        if (!inputHealthy || _raw.length2 != 0) throw StateError('需要新鲜的回中输入');
        if (command == 'enable') {
          if (state['can_enable'] != true) {
            throw StateError(state['block_reason']?.toString() ?? '当前不允许使能');
          }
          _paused = false;
          _intent = true;
          _needNeutral = false;
          _enabled.add(true);
        } else if (command == 'stand' || command == 'sit') {
          if (state['armed'] != true) throw StateError('请先使能或恢复操控');
          _needNeutral = true;
          _directions.add(Vector3.zero());
          if (command == 'stand') {
            _stand.add(true);
          } else {
            _sit.add(true);
          }
        } else if (command == 'model') {
          final slot = body['slot'];
          if (slot != 'flat' && slot != 'stairs') {
            throw StateError('仅支持平地和楼梯槽位');
          }
          if (state['armed'] != true || state['can_switch'] != true) {
            throw StateError('切换需要使能完成、回中，且处于趴地或L1站立状态');
          }
          _busy = true;
          _needNeutral = true;
          try {
            await _selectSlot(slot as String);
          } finally {
            _busy = false;
          }
        } else if (command == 'zero') {
          if (_intent ||
              state['motor_enabled'] == true ||
              state['can_zero'] != true ||
              body['confirmation'] != 'ALL_16_AT_MECHANICAL_ZERO') {
            throw StateError('标零需要未使能、趴地、16关节健康静止，并确认规定机械零位');
          }
          _busy = true;
          _needNeutral = true;
          try {
            final result = await _zeroAll();
            if (result['verified'] != 16) {
              throw StateError('16 motor zero verification was not confirmed');
            }
            if (identical(socket, _socket)) {
              _send({'type': 'ack', 'id': id, 'ok': true, 'result': result});
            }
          } on ZeroNotStarted {
            rethrow;
          } catch (_) {
            _zeroFailed = true;
            _pause();
            rethrow;
          } finally {
            _busy = false;
          }
          _sendStatus();
          return;
        } else {
          throw StateError('未知指令');
        }
      }
      if (identical(socket, _socket)) {
        _send({
          'type': 'ack',
          'id': id,
          'ok': true,
          'result': {'accepted': true},
        });
      }
      _sendStatus();
    } catch (error) {
      if (error is FormatException) _pause();
      if (identical(socket, _socket)) {
        _send({
          'type': id == null ? 'error' : 'ack',
          'id': id,
          'ok': false,
          'error': error.toString().replaceFirst(
            RegExp(r'^(Bad state: |FormatException: )'),
            '',
          ),
        });
        _sendStatus();
      }
    }
  }

  Future<void> close() async {
    if (_disposed) return;
    _pause();
    _disposed = true;
    _watchdog?.cancel();
    _statusTimer?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close(WebSocketStatus.goingAway);
    await _server?.close(force: true);
    for (final stream in <StreamController<dynamic>>[
      _directions,
      _stand,
      _sit,
      _idle,
      _enabled,
      _red,
      _calibrate,
      _switch,
      _hardStops,
    ]) {
      await stream.close();
    }
    _sessions.clear();
  }

  @override
  void dispose() => unawaited(close());
}
