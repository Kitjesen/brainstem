import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:serial_port/serial_port.dart';
import 'support.dart';

export 'package:serial_port/serial_port.dart';

final _logger = Logger('SerialPortController');

class SerialPortController<E, S> {
  final SerialPort _serialPort;

  final _eventConverter = eventConverter[E]! as Uint8List Function(E);
  final _stateConverter =
      stateConverter[S]! as Stream<Iterable<S>> Function(Stream<Uint8List>);

  SerialPortController(
    String portName, {
    int baudRate = 115200,
    Parity parity = .ParityNone,
    DataBits dataBits = .DataBits8,
    StopBits stopbits = .StopOne,
    FlowControl flowControl = .FlowNone,
    int readBufferSize = 4096,
  }) : _serialPort = SerialPort()
         ..init(
           portName,
           baudRate,
           parity,
           dataBits,
           stopbits,
           flowControl,
           readBufferSize,
         );

  bool open() {
    final result = _serialPort.open();
    if (!result) {
      _logger.severe(
        'open ${_serialPort.portName} failed: ${_serialPort.lastErrorMessage}',
      );
      return false;
    }
    _logger.info('${_serialPort.portName} opened successfully.');
    return true;
  }

  void add(E event) {
    try {
      _serialPort.write(_eventConverter(event));
    } catch (e, st) {
      _logger.severe('Serial write failed on ${_serialPort.portName}', e, st);
    }
  }

  Stream<Iterable<S>> get state => _stateConverter(_serialPort.onData);

  bool _disposed = false;

  void close() {
    if (_disposed) return;
    _logger.info('Closing ${_serialPort.portName}.');
    _serialPort.close();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _logger.info('Disposing ${_serialPort.portName}.');
    _serialPort.dispose();
  }
}
