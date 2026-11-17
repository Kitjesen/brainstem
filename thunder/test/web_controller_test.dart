import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:thunder/src/web_controller.dart';
import 'package:thunder/src/web_zero_stability.dart';
import 'package:test/test.dart';

const token = 'unit-test-token-not-for-real-hardware-123456789';

class Peer {
  final WebSocket socket;
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final statuses = <Map<String, dynamic>>[];
  late final StreamSubscription<dynamic> subscription;
  Timer? timer;
  int sequence = 0;
  List<num> axes = [0, 0, 0];

  Peer(this.socket) {
    subscription = socket.listen((raw) {
      final event = jsonDecode(raw as String) as Map<String, dynamic>;
      if (event['type'] == 'status') statuses.add(event);
      events.add(event);
    });
    input();
    timer = Timer.periodic(const Duration(milliseconds: 40), (_) => input());
  }

  void input() => socket.add(
    jsonEncode({'type': 'input', 'seq': ++sequence, 'axes': axes}),
  );

  Future<Map<String, dynamic>> command(
    String name, [
    Map<String, Object?> extra = const {},
  ]) {
    final id = 'test-${++sequence}';
    final next = events.stream
        .firstWhere((e) => e['type'] == 'ack' && e['id'] == id)
        .timeout(const Duration(seconds: 3));
    socket.add(
      jsonEncode({
        'type': 'command',
        'seq': sequence,
        'id': id,
        'command': name,
        ...extra,
      }),
    );
    return next;
  }

  Future<Map<String, dynamic>> status(
    bool Function(Map<String, dynamic>) predicate,
  ) {
    if (statuses.isNotEmpty && predicate(statuses.last)) {
      return Future.value(statuses.last);
    }
    return events.stream
        .firstWhere((e) => e['type'] == 'status' && predicate(e))
        .timeout(const Duration(seconds: 3));
  }

  Future<void> close() async {
    timer?.cancel();
    await socket.close();
    await subscription.cancel();
    await events.close();
  }
}

void main() {
  late Directory assets;
  late WebController controller;
  late HttpClient client;
  late String origin;
  late Map<String, Object?> state;
  late List<bool> enableEvents;
  late List<List<double>> directions;
  late int hardStops;
  late int zeroCalls;
  late int modelCalls;
  late bool failZero;
  late bool refuseZero;
  late bool failStatus;
  final peers = <Peer>[];
  final subscriptions = <StreamSubscription<dynamic>>[];

  Future<(int, String, List<Cookie>)> http(
    String method,
    String path, {
    Object? body,
    String? from,
    String? cookie,
  }) async {
    final request = await client.openUrl(method, Uri.parse('$origin$path'));
    if (from != null) request.headers.set('Origin', from);
    if (cookie != null) request.headers.set('Cookie', cookie);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    return (
      response.statusCode,
      await utf8.decoder.bind(response).join(),
      response.cookies,
    );
  }

  Future<String> login() async {
    final response = await http(
      'POST',
      '/api/session',
      from: origin,
      body: {'token': token},
    );
    expect(response.$1, 200);
    final cookie = response.$3.single;
    expect(cookie.httpOnly, isTrue);
    expect(cookie.sameSite, SameSite.strict);
    return '${cookie.name}=${cookie.value}';
  }

  Future<Peer> connect([String? cookie]) async {
    cookie ??= await login();
    final socket = await WebSocket.connect(
      '${origin.replaceFirst('http', 'ws')}/ws',
      headers: {'Origin': origin, 'Cookie': cookie},
    );
    final peer = Peer(socket);
    peers.add(peer);
    await peer.status((s) => s['input_healthy'] == true);
    return peer;
  }

  setUp(() async {
    enableEvents = [];
    directions = [];
    hardStops = 0;
    zeroCalls = 0;
    modelCalls = 0;
    failZero = false;
    refuseZero = false;
    failStatus = false;
    state = {
      'ready': true,
      'preview': true,
      'cms': 'GROUNDED',
      'motor_enabled': false,
      'can_enable': true,
      'can_switch': true,
      'can_zero': true,
      'can_open_zero': true,
      'model_slot': 'flat',
      'model_profile': 'test-flat',
      'limits': {'vx': 1.0, 'vy': 1.0, 'yaw': 1.0},
    };
    assets = await Directory.systemTemp.createTemp('thunder_web_test_');
    for (final name in ['index.html', 'styles.css', 'app.js']) {
      File('${assets.path}/$name').writeAsStringSync('fixture');
    }
    controller = WebController(
      token: token,
      assetsPath: assets.path,
      status: () {
        if (failStatus) throw StateError('status unavailable');
        return state;
      },
      selectSlot: (slot) async {
        modelCalls++;
        state['model_slot'] = slot;
      },
      zeroAll: () async {
        zeroCalls++;
        if (refuseZero) throw const ZeroNotStarted('等待关节稳定：FR Hip');
        if (failZero) throw StateError('verification incomplete');
        return {'verified': 16, 'power_cycle_verified': false};
      },
    );
    subscriptions.add(
      controller.enabled.listen((value) {
        enableEvents.add(value);
        state['motor_enabled'] = value;
      }),
    );
    subscriptions.add(
      controller.direction.listen((v) => directions.add([v.x, v.y, v.z])),
    );
    subscriptions.add(controller.hardStop.listen((_) => hardStops++));
    await controller.start();
    origin = 'http://127.0.0.1:${controller.boundPort}';
    client = HttpClient();
  });

  tearDown(() async {
    for (final peer in peers) {
      await peer.close();
    }
    peers.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    await controller.close();
    client.close(force: true);
    await assets.delete(recursive: true);
  });

  test(
    'public UI is inert; protected status/login require token and origin',
    () async {
      expect((await http('GET', '/')).$1, 200);
      expect((await http('GET', '/api/status')).$1, 401);
      expect(
        (await http(
          'POST',
          '/api/session',
          from: 'http://evil.invalid',
          body: {'token': token},
        )).$1,
        403,
      );
      expect(
        (await http(
          'POST',
          '/api/session',
          from: origin,
          body: {'token': 'bad'},
        )).$1,
        401,
      );
      final cookie = await login();
      expect((await http('GET', '/api/status', cookie: cookie)).$1, 200);
      expect((await http('GET', '/%2e%2e/pubspec.yaml')).$1, 404);
      expect(enableEvents, isEmpty);
      expect(zeroCalls, 0);
      expect(modelCalls, 0);
    },
  );

  test(
    'unauthenticated/cross-origin WebSockets and a second controller fail',
    () async {
      await expectLater(
        WebSocket.connect(
          '${origin.replaceFirst('http', 'ws')}/ws',
          headers: {'Origin': origin},
        ),
        throwsA(isA<WebSocketException>()),
      );
      final cookie = await login();
      await expectLater(
        WebSocket.connect(
          '${origin.replaceFirst('http', 'ws')}/ws',
          headers: {'Origin': 'http://evil.invalid', 'Cookie': cookie},
        ),
        throwsA(isA<WebSocketException>()),
      );
      await connect(cookie);
      await expectLater(
        WebSocket.connect(
          '${origin.replaceFirst('http', 'ws')}/ws',
          headers: {'Origin': origin, 'Cookie': cookie},
        ),
        throwsA(isA<WebSocketException>()),
      );
      expect(enableEvents, isEmpty);
    },
  );

  test(
    'movement needs explicit enable and standing; normal release is not hard stop',
    () async {
      final peer = await connect();
      peer.axes = [1, 0, 0];
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(directions.every((v) => v.every((n) => n == 0)), isTrue);
      expect((await peer.command('enable'))['ok'], isFalse);
      peer.axes = [0, 0, 0];
      peer.input();
      expect((await peer.command('enable'))['ok'], isTrue);
      state['cms'] = 'STANDING';
      peer.axes = [0.5, -0.5, 0.4];
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(directions.last[0], closeTo(0.5, 1e-6));
      expect(directions.last[1], closeTo(-0.5, 1e-6));
      expect(directions.last[2], closeTo(0.4, 1e-6));
      peer.axes = [0, 0, 0];
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(directions.last, [0.0, 0.0, 0.0]);
      expect(hardStops, 0);
      expect(enableEvents, [true]);
    },
  );

  test(
    'watchdog stops motion without dropping support and requires explicit rearm',
    () async {
      final peer = await connect();
      await peer.command('enable');
      state['cms'] = 'WALKING';
      peer.axes = [1, 0, 0];
      peer.input();
      peer.timer!.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(hardStops, 1);
      expect(directions.last, [0.0, 0.0, 0.0]);
      expect(enableEvents, [true]);
      expect(state['motor_enabled'], isTrue);
      expect(controller.hardStopActive, isTrue);
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(directions.last, [0.0, 0.0, 0.0]);
      peer.axes = [0, 0, 0];
      peer.input();
      expect((await peer.command('enable'))['ok'], isTrue);
      expect(controller.hardStopActive, isFalse);
    },
  );

  test(
    'disconnect and new browser do not auto-enable or replay motion',
    () async {
      final first = await connect();
      await first.command('enable');
      state['cms'] = 'WALKING';
      first.axes = [1, 0, 0];
      first.input();
      first.timer!.cancel();
      await first.socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = await connect();
      expect(enableEvents, [true]);
      expect(
        (await second.status((s) => s['input_healthy'] == true))['armed'],
        isFalse,
      );
      second.axes = [1, 0, 0];
      second.input();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(directions.last, [0.0, 0.0, 0.0]);
    },
  );

  test(
    'stale and invalid axes latch a stop, never forwarding the packet',
    () async {
      final peer = await connect();
      await peer.command('enable');
      state['cms'] = 'WALKING';
      peer.socket.add(
        jsonEncode({
          'type': 'input',
          'seq': peer.sequence,
          'axes': [1, 0, 0],
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.hardStopActive, isTrue);
      expect(directions.last, [0.0, 0.0, 0.0]);
      peer.input();
      await peer.command('enable');
      peer.socket.add(
        jsonEncode({
          'type': 'input',
          'seq': ++peer.sequence,
          'axes': [2, 0, 0],
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.hardStopActive, isTrue);
      expect(directions.any((v) => v[0] == 2), isFalse);
    },
  );

  test('model command uses only the two slots and runtime gate', () async {
    final peer = await connect();
    expect((await peer.command('model', {'slot': 'stairs'}))['ok'], isFalse);
    await peer.command('enable');
    expect(
      (await peer.command('model', {'slot': 'historical-profile'}))['ok'],
      isFalse,
    );
    state['can_switch'] = false;
    expect((await peer.command('model', {'slot': 'stairs'}))['ok'], isFalse);
    expect(modelCalls, 0);
    state['can_switch'] = true;
    expect((await peer.command('model', {'slot': 'stairs'}))['ok'], isTrue);
    expect(state['model_slot'], 'stairs');
    expect(modelCalls, 1);
  });

  test(
    'zero requires explicit mechanical confirmation and actual disabled state',
    () async {
      final peer = await connect();
      expect((await peer.command('zero'))['ok'], isFalse);
      await peer.command('enable');
      expect(
        (await peer.command('zero', {
          'confirmation': 'ALL_16_AT_MECHANICAL_ZERO',
        }))['ok'],
        isFalse,
      );
      await peer.command('disable');
      state['can_zero'] = false;
      expect(
        (await peer.command('zero', {
          'confirmation': 'ALL_16_AT_MECHANICAL_ZERO',
        }))['ok'],
        isFalse,
      );
      state['can_zero'] = true;
      final ack = await peer.command('zero', {
        'confirmation': 'ALL_16_AT_MECHANICAL_ZERO',
      });
      expect(ack['ok'], isTrue);
      expect((ack['result'] as Map)['verified'], 16);
      expect(zeroCalls, 1);
    },
  );

  test(
    'failed calibration blocks enable and repeat zero rather than reporting success',
    () async {
      final peer = await connect();
      failZero = true;
      expect(
        (await peer.command('zero', {
          'confirmation': 'ALL_16_AT_MECHANICAL_ZERO',
        }))['ok'],
        isFalse,
      );
      expect((await peer.command('enable'))['ok'], isFalse);
      expect(
        (await peer.command('zero', {
          'confirmation': 'ALL_16_AT_MECHANICAL_ZERO',
        }))['ok'],
        isFalse,
      );
      expect(zeroCalls, 1);
      expect(enableEvents, isEmpty);
      final status = await peer.status((s) => s['zero_phase'] == 'uncertain');
      expect(status['can_open_zero'], false);
      expect(status['zero_block_reason'], contains('不要重复标零'));
    },
  );

  test(
    'pre-write refusal does not latch or automatically retry zero',
    () async {
      final peer = await connect();
      refuseZero = true;
      final ack = await peer.command('zero', {
        'confirmation': 'ALL_16_AT_MECHANICAL_ZERO',
      });
      expect(ack['ok'], false);
      expect(ack['error'], contains('尚未写入零点'));
      expect(zeroCalls, 1);
      expect(
        (await peer.status((s) => s['can_enable'] == true))['can_open_zero'],
        true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(zeroCalls, 1);
      expect(enableEvents, isEmpty);
      refuseZero = false;
      expect(
        (await peer.command('zero', {
          'confirmation': 'ALL_16_AT_MECHANICAL_ZERO',
        }))['ok'],
        true,
      );
      expect(zeroCalls, 2);
    },
  );

  test(
    'pending runtime cannot emit commands and status is not optimistic',
    () async {
      state['ready'] = false;
      final peer = await connect();
      for (final command in ['enable', 'stand', 'sit', 'model', 'zero']) {
        expect((await peer.command(command))['ok'], isFalse);
      }
      expect(enableEvents, isEmpty);
      expect(zeroCalls, 0);
      expect(modelCalls, 0);
    },
  );

  test(
    'held movement during a transition is not replayed after standing',
    () async {
      final peer = await connect();
      await peer.command('enable');
      state['cms'] = 'TRANSITIONING';
      peer.axes = [1, 0, 0];
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      state['cms'] = 'STANDING';
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(directions.last, [0.0, 0.0, 0.0]);
      peer.axes = [0, 0, 0];
      peer.input();
      peer.axes = [1, 0, 0];
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(directions.last, [1.0, 0.0, 0.0]);
    },
  );

  test('stop and disable remain available when runtime status fails', () async {
    final peer = await connect();
    await peer.command('enable');
    state['ready'] = false;
    expect((await peer.command('stop'))['ok'], isTrue);
    expect(directions.last, [0.0, 0.0, 0.0]);
    failStatus = true;
    expect((await peer.command('disable'))['ok'], isTrue);
    expect(enableEvents.last, isFalse);
    expect((await peer.command('enable'))['ok'], isFalse);
  });

  test(
    'late input cannot beat the watchdog timer and resume control',
    () async {
      await controller.close();
      controller = WebController(
        token: token,
        assetsPath: assets.path,
        status: () => state,
        selectSlot: (_) async {},
        zeroAll: () async => {},
        watchdogInterval: const Duration(seconds: 10),
      );
      subscriptions.add(
        controller.enabled.listen((value) {
          enableEvents.add(value);
          state['motor_enabled'] = value;
        }),
      );
      subscriptions.add(
        controller.direction.listen((v) {
          directions.add([v.x, v.y, v.z]);
        }),
      );
      await controller.start();
      origin = 'http://127.0.0.1:${controller.boundPort}';
      final peer = await connect();
      await peer.command('enable');
      state['cms'] = 'WALKING';
      peer.timer?.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      peer.axes = [1, 0, 0];
      peer.input();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.hardStopActive, isTrue);
      expect(directions.last, [0.0, 0.0, 0.0]);
      expect(enableEvents, [true]);
    },
  );
}
