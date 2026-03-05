import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'cserialport.g.dart';

class SerialPort {
  final int _handle;
  final StreamController<Uint8List> _dataReceivedController;
  Stream<Uint8List> get onData => _dataReceivedController.stream;
  final ffi.NativeCallable<pFunReadEventFunction> _readCallback;
  // TODO: hot plug event 会导致无法结束程序
  // final StreamController<bool> _hotPlugController;
  // final NativeCallable<pFunHotPlugEventFunction> _hotPlugCallback;
  SerialPort._(
    this._handle,
    this._dataReceivedController,
    this._readCallback,
    // this._hotPlugController,
    // this._hotPlugCallback,
  );
  factory SerialPort() {
    final newHandle = CSerialPortMalloc();

    /// Register a callback function to be called when data is received on the serial port.
    /// https://flutter.dev/flutter/dart-ffi/NativeCallable/NativeCallable.listener.html
    final onDataReceivedController = StreamController<Uint8List>();
    void onListen(int handle, ffi.Pointer<ffi.Char> portNamePtr, int size) {
      assert(handle == newHandle, 'Handle mismatch: $handle');
      final data = SerialPort._read(handle, size);
      onDataReceivedController.add(data);
    }

    final readCallback = ffi.NativeCallable<pFunReadEventFunction>.listener(
      onListen,
    );
    CSerialPortConnectReadEvent(newHandle, readCallback.nativeFunction);

    // final hotPlugController = StreamController<bool>();
    // void onHotPlugin(
    //   Darti_handle_t handle,
    //   Pointer<Char> portNamePtr,
    //   int isAdd,
    // ) {
    //   assert(handle == newHandle, 'Handle mismatch: $handle');
    //   // final portName = portNamePtr.cast<Utf8>().toDartString();
    //   hotPlugController.add(isAdd != 0);
    // }

    // final hotPlugCallback = NativeCallable<pFunHotPlugEventFunction>.listener(
    //   onHotPlugin,
    // );
    // CSerialPortConnectHotPlugEvent(
    //   newHandle,
    //   hotPlugCallback.nativeFunction,
    // );

    return ._(
      newHandle,
      onDataReceivedController,
      readCallback,
      // hotPlugController,
      // hotPlugCallback,
    );
  }
  void dispose() {
    close(); // 先关闭，避免回调触发

    _readCallback.close();
    CSerialPortDisconnectReadEvent(_handle);
    _dataReceivedController.close();

    // _hotPlugController.close();
    // _hotPlugCallback.close();
    // CSerialPortDisconnectHotPlugEvent(_handle);

    CSerialPortFree(_handle);
  }

  void init(
    String portName, [
    int baudRate = 115200,
    Parity parity = .ParityNone,
    DataBits dataBits = .DataBits8,
    StopBits stopbits = .StopOne,
    FlowControl flowControl = .FlowNone,
    int readBufferSize = 4096,
  ]) {
    final portNamePtr = portName.toNativeUtf8();
    try {
      CSerialPortInit(
        _handle,
        portNamePtr.cast(),
        baudRate,
        parity,
        dataBits,
        stopbits,
        flowControl,
        readBufferSize,
      );
    } finally {
      malloc.free(portNamePtr);
    }
  }

  bool open() {
    final result = CSerialPortOpen(_handle);
    if (result != 0) return true;
    return false;
  }

  void close() {
    CSerialPortClose(_handle);
  }

  static Uint8List _read(int handle, int size) => using((arena) {
    final buffer = arena<ffi.Uint8>(size);
    final readedLen = CSerialPortReadData(handle, buffer.cast(), size);
    return .fromList(buffer.asTypedList(readedLen));
  });

  int get lastErrorCode => CSerialPortGetLastError(_handle);
  String get lastErrorMessage {
    final messagePtr = CSerialPortGetLastErrorMsg(_handle);
    return messagePtr.cast<Utf8>().toDartString();
  }

  bool get isOpen => CSerialPortIsOpen(_handle) != 0;
  int get readBufferUsedLen => CSerialPortGetReadBufferUsedLen(_handle);

  int write(Uint8List data) => using((arena) {
    final buffer = arena<ffi.Uint8>(data.length);
    final typedData = buffer.asTypedList(data.length);
    typedData.setAll(0, data);
    return CSerialPortWriteData(_handle, buffer.cast(), data.length);
  });

  bool flushBuffers() => CSerialPortFlushBuffers(_handle) != 0;
  bool flushReadBuffers() => CSerialPortFlushReadBuffers(_handle) != 0;
  bool flushWriteBuffers() => CSerialPortFlushWriteBuffers(_handle) != 0;

  String get portName =>
      CSerialPortGetPortName(_handle).cast<Utf8>().toDartString();

  set portName(String name) {
    final namePtr = name.toNativeUtf8();
    try {
      CSerialPortSetPortName(_handle, namePtr.cast());
    } finally {
      malloc.free(namePtr);
    }
  }

  int get readIntervalTimeout => CSerialPortGetReadIntervalTimeout(_handle);
  set readIntervalTimeout(int millisecond) =>
      CSerialPortSetReadIntervalTimeout(_handle, millisecond);

  int get baudRate => CSerialPortGetBaudRate(_handle);
  set baudRate(int rate) => CSerialPortSetBaudRate(_handle, rate);

  Parity get parity => CSerialPortGetParity(_handle);
  set parity(Parity parity) => CSerialPortSetParity(_handle, parity);

  DataBits get dataBits => CSerialPortGetDataBits(_handle);
  set dataBits(DataBits bits) => CSerialPortSetDataBits(_handle, bits);

  StopBits get stopBits => CSerialPortGetStopBits(_handle);
  set stopBits(StopBits bits) => CSerialPortSetStopBits(_handle, bits);

  FlowControl get flowControl => CSerialPortGetFlowControl(_handle);
  set flowControl(FlowControl flow) => CSerialPortSetFlowControl(_handle, flow);

  int get readBufferSize => CSerialPortGetReadBufferSize(_handle);
  set readBufferSize(int size) => CSerialPortSetReadBufferSize(_handle, size);

  set dtr(bool enable) => CSerialPortSetDtr(_handle, enable ? 1 : 0);
  set rts(bool enable) => CSerialPortSetRts(_handle, enable ? 1 : 0);
}
