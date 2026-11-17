import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:onnx_runtime/onnx_runtime.dart';
import 'observation_history.dart';
import 'recovery.dart';

class OnnxRecoveryInference implements RecoveryInference {
  static const modelSha =
      '4cc6c0942106644e1305879cae497206e18cf9530782635702d77f73005bd5c5';
  final _events = ReceivePort();
  final _ready = Completer<void>(), _exited = Completer<void>();
  Completer<Map<String, dynamic>>? _pending;
  Map<String, dynamic>? _expected;
  Isolate? _isolate;
  SendPort? _commands;
  bool _closed = false, _failed = false;
  Future<void>? _closing;
  List<double> lastFeatures = const [];
  List<double> lastRawAction = const [];
  final warmupUs = <int>[];

  OnnxRecoveryInference._() {
    _events.listen(_receive);
  }

  static Future<OnnxRecoveryInference> start(
    String modelPath, {
    String expectedSha = modelSha,
  }) async {
    final bytes = await File(modelPath).readAsBytes();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha) ||
        sha256.convert(bytes).toString() != expectedSha) {
      throw StateError('Recovery ONNX identity mismatch');
    }
    final client = OnnxRecoveryInference._();
    try {
      client._isolate = await Isolate.spawn(
        _worker,
        [
          client._events.sendPort,
          TransferableTypedData.fromList([bytes]),
        ],
        onError: client._events.sendPort,
        onExit: client._events.sendPort,
        errorsAreFatal: true,
      );
      await client._ready.future.timeout(const Duration(seconds: 30));
      // Warm Dart preprocessing and isolate delivery before any operator can arm.
      await client.reset(0);
      final sample = RecoverySample(
        angular: [0, 0, 0],
        gravity: [0, 0, -1],
        q: [...RecoveryController.nominal, 0, 0, 0, 0],
        dq: List.filled(16, 0),
        ageMs: 0,
        healthy: true,
      );
      for (var seq = 0; seq < 20; seq++) {
        final watch = Stopwatch()..start();
        await client.infer(0, seq, sample).timeout(const Duration(seconds: 2));
        client.warmupUs.add(watch.elapsedMicroseconds);
      }
      client.lastFeatures = const [];
      client.lastRawAction = const [];
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  void _fail(Object error) {
    _failed = true;
    if (!_ready.isCompleted) _ready.completeError(error);
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  void _receive(dynamic message) {
    if (message == null) {
      if (!_exited.isCompleted) _exited.complete();
      if (!_closed) _fail(StateError('Recovery ONNX isolate exited'));
      return;
    }
    if (_closed) return;
    try {
      if (message is! Map || message['kind'] == 'error') {
        throw StateError('Recovery ONNX worker error: $message');
      }
      if (!_ready.isCompleted) {
        if (message['kind'] != 'ready' || message['port'] is! SendPort) {
          throw StateError('Invalid ONNX ready');
        }
        _commands = message['port'] as SendPort;
        _ready.complete();
        return;
      }
      if (_pending == null ||
          message['kind'] != _expected!['kind'] ||
          message['epoch'] != _expected!['epoch'] ||
          message['seq'] != _expected!['seq']) {
        throw StateError('Stale or unexpected ONNX response');
      }
      final pending = _pending!;
      _pending = null;
      pending.complete(Map<String, dynamic>.from(message));
    } catch (error) {
      _fail(error);
    }
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> message) {
    if (_closed || _failed || _commands == null || _pending != null) {
      throw StateError('ONNX worker unavailable/busy');
    }
    final pending = Completer<Map<String, dynamic>>();
    _pending = pending;
    _expected = message;
    _commands!.send(message);
    return pending.future;
  }

  @override
  Future<void> reset(int epoch) async {
    await _request({'kind': 'reset', 'epoch': epoch});
  }

  @override
  Future<List<double>> infer(int epoch, int seq, RecoverySample sample) async {
    sample.validate();
    final result = await _request({
      'kind': 'infer',
      'epoch': epoch,
      'seq': seq,
      'angular': sample.angular,
      'gravity': sample.gravity,
      'q': sample.q,
      'dq': sample.dq,
      'ageMs': sample.ageMs,
      'healthy': sample.healthy,
    });
    final raw = (result['raw'] as List).cast<double>();
    final features = (result['features'] as List).cast<double>();
    if (raw.length != 16 ||
        features.length != 56 ||
        [...raw, ...features].any((v) => !v.isFinite) ||
        raw.any((v) => v.abs() > 4)) {
      _fail(StateError('Invalid native ONNX result'));
      throw StateError('Invalid native ONNX result');
    }
    lastFeatures = List.unmodifiable(features);
    lastRawAction = List.unmodifiable(raw);
    return List.unmodifiable(raw);
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _fail(StateError('Recovery ONNX closed'));
    if (_commands != null) {
      _commands!.send({'kind': 'close'});
    } else {
      _isolate?.kill();
    }
    if (_isolate != null) {
      try {
        await _exited.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        // Never free native state from another isolate while Run may be active.
        _isolate?.kill();
        throw StateError(
          'ONNX worker did not close; restart its owning process',
        );
      } finally {
        _events.close();
      }
    } else {
      _events.close();
    }
  }

  static Future<void> _worker(List<Object> args) async {
    final replies = args[0] as SendPort;
    final commands = ReceivePort();
    OnnxEnv? env;
    InferenceSession? session;
    try {
      final bytes = (args[1] as TransferableTypedData)
          .materialize()
          .asUint8List();
      env = OnnxEnv.create(
        OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
        'recovery_isolate',
      );
      session = InferenceSession.create(
        env,
        bytes,
        const SessionOptions(intraOpNumThreads: 1, interOpNumThreads: 1),
      );
      if (session.inputCounts != 1 ||
          session.outputCounts != 2 ||
          session.getInputName(0) != 'history' ||
          session.getOutputName(0) != 'raw_action' ||
          session.getOutputName(1) != 'features') {
        throw StateError('Wrong ONNX interface');
      }
      final warm = Float32List(360);
      for (var i = 0; i < 6; i++) {
        warm[i * 60 + 5] = -1;
        warm[i * 60 + 57] = 2;
        warm[i * 60 + 59] = 1;
      }
      for (var i = 0; i < 20; i++) {
        session.run({
          'history': OnnxFloat(value: warm, shape: [1, 360]),
        });
      }
      final history = RecoveryObservationHistory();
      int? epoch;
      var next = 0;
      replies.send({'kind': 'ready', 'port': commands.sendPort});
      await for (final dynamic value in commands) {
        final message = value as Map;
        if (message['kind'] == 'close') break;
        if (message['epoch'] is! int) throw StateError('Invalid ONNX epoch');
        final e = message['epoch'] as int;
        if (message['kind'] == 'reset') {
          if (e < 0 || (epoch != null && e <= epoch)) {
            throw StateError('Reset must advance epoch');
          }
          epoch = e;
          next = 0;
          history.reset();
          replies.send({'kind': 'reset', 'epoch': e});
          continue;
        }
        if (message['kind'] != 'infer' ||
            epoch != e ||
            message['seq'] != next) {
          throw StateError('ONNX session/sequence mismatch');
        }
        final sample = RecoverySample(
          angular: (message['angular'] as List).cast<double>(),
          gravity: (message['gravity'] as List).cast<double>(),
          q: (message['q'] as List).cast<double>(),
          dq: (message['dq'] as List).cast<double>(),
          ageMs: message['ageMs'] as int,
          healthy: message['healthy'] as bool,
        );
        final input = history.append(sample);
        final (_, output) = session.run({
          'history': OnnxFloat(value: input, shape: [1, 360]),
        });
        final raw = (output[0] as OnnxFloat).value,
            features = (output[1] as OnnxFloat).value;
        if (features.length != 56 || features.any((v) => !v.isFinite)) {
          throw StateError('Invalid features');
        }
        history.commit(raw);
        replies.send({
          'kind': 'infer',
          'epoch': e,
          'seq': next++,
          'raw': raw,
          'features': features,
        });
      }
    } catch (error, stack) {
      replies.send({'kind': 'error', 'error': '$error', 'stack': '$stack'});
    } finally {
      commands.close();
      session?.dispose();
      env?.dispose();
    }
  }
}
