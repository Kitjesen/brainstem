import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:pcan/pcan.dart';
import 'package:serial_port/serial_port.dart';

final _log = Logger('RobStrideAtPcan');

/// RobStride USB-CAN AT mode: AT + ((extended CAN ID << 3) | 4) + DLC + data + CRLF.
Uint8List encodeRobStrideAt(PcanMessage message) {
  if (message.type != PcanMessageType.extended ||
      message.id < 0 ||
      message.id > 0x1fffffff ||
      message.length > 8) {
    throw ArgumentError('AT transport requires a classic extended CAN frame');
  }
  final bytes = Uint8List(9 + message.length);
  bytes[0] = 0x41;
  bytes[1] = 0x54;
  ByteData.sublistView(bytes).setUint32(2, (message.id << 3) | 4);
  bytes[6] = message.length;
  bytes.setRange(7, 7 + message.length, message.data);
  bytes[bytes.length - 2] = 0x0d;
  bytes[bytes.length - 1] = 0x0a;
  return bytes;
}

class RobStrideAtDecoder {
  final _buffer = <int>[];

  Iterable<PcanMessage> add(Uint8List bytes) sync* {
    _buffer.addAll(bytes);
    while (_buffer.length >= 2) {
      if (_buffer[0] != 0x41 || _buffer[1] != 0x54) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < 7) return;
      final dlc = _buffer[6];
      if (dlc > 8) {
        _buffer.removeAt(0);
        continue;
      }
      final length = 9 + dlc;
      if (_buffer.length < length) return;
      final packed = ByteData.sublistView(
        Uint8List.fromList(_buffer.sublist(2, 6)),
      ).getUint32(0);
      if ((packed & 7) != 4 ||
          _buffer[length - 2] != 0x0d ||
          _buffer[length - 1] != 0x0a) {
        _buffer.removeAt(0);
        continue;
      }
      final message = PcanMessage(
        id: packed >> 3,
        type: PcanMessageType.extended,
        data: Uint8List.fromList(_buffer.sublist(7, 7 + dlc)),
      );
      _buffer.removeRange(0, length);
      yield message;
    }
  }

  void clear() => _buffer.clear();
}

/// Reuses PcanController's RS decoding, stop ordering and bounded write retries.
class RobStrideAtPcan extends Pcan {
  final String portName;
  final SerialPort Function() _createPort;
  SerialPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  final _decoder = RobStrideAtDecoder();
  final _received = Queue<PcanMessage>();
  PcanStatus _status = PcanStatus.initialize;

  RobStrideAtPcan(this.portName, {SerialPort Function()? createPort})
    : _createPort = createPort ?? SerialPort.new,
      super(PcanChannel.nonebus);

  @override
  String get transportName => 'AT($portName,921600)';

  @override
  int? get lastWriteErrno => _port?.lastErrorCode;

  @override
  PcanStatus get status => _status;

  @override
  PcanStatus open([PcanBaudRate baudRate = PcanBaudRate.baud1M]) {
    if (_port != null) return PcanStatus.hwinuse;
    if (baudRate != PcanBaudRate.baud1M) return PcanStatus.illparamval;
    try {
      final port = _port = _createPort();
      port.init(portName, 921600);
      _subscription = port.onData.listen(
        (bytes) {
          if (_status != PcanStatus.ok) return;
          for (final frame in _decoder.add(bytes)) {
            if (_received.length >= 512) {
              _received.clear();
              _status = PcanStatus.qoverrun;
              _log.severe('$transportName receive queue overflow');
              return;
            }
            _received.add(frame);
          }
        },
        onError: (Object error, StackTrace stack) {
          _status = PcanStatus.busoff;
          _log.severe('$transportName receive failed', error, stack);
        },
        onDone: () => _status = PcanStatus.busoff,
      );
      if (!port.open()) {
        _log.severe('$transportName open failed: ${port.lastErrorMessage}');
        close();
        return PcanStatus.illhw;
      }
      port.readIntervalTimeout = 1;
      return _status = PcanStatus.ok;
    } catch (error, stack) {
      _log.severe('$transportName open failed', error, stack);
      close();
      return PcanStatus.illhw;
    }
  }

  @override
  PcanStatus write(PcanMessage message) {
    if (_status != PcanStatus.ok) return _status;
    final Uint8List bytes;
    try {
      bytes = encodeRobStrideAt(message);
    } on ArgumentError {
      return PcanStatus.illdata;
    }
    try {
      final count = _port!.write(bytes);
      if (count == bytes.length) return PcanStatus.ok;
      // A partial frame must not be retried in full on the same byte stream.
      _log.severe('$transportName short write: $count/${bytes.length}');
    } catch (error, stack) {
      _log.severe('$transportName write failed', error, stack);
    }
    return _status = PcanStatus.busoff;
  }

  @override
  (PcanMessage, PcanTimestamp, PcanStatus) read() {
    final result = _status == PcanStatus.ok
        ? (_received.isEmpty ? PcanStatus.qrcvempty : PcanStatus.ok)
        : _status;
    return (
      result == PcanStatus.ok
          ? _received.removeFirst()
          : PcanMessage(
              id: 0,
              type: PcanMessageType.extended,
              data: Uint8List(0),
            ),
      PcanTimestamp(millis: 0, millisOverflow: 0, micros: 0),
      result,
    );
  }

  @override
  PcanStatus reset() {
    close();
    return open();
  }

  @override
  PcanStatus close() {
    _status = PcanStatus.initialize;
    _subscription?.cancel();
    _subscription = null;
    _port?.dispose();
    _port = null;
    _decoder.clear();
    _received.clear();
    return PcanStatus.ok;
  }
}
