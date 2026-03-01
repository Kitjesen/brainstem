import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'ffi/onnx_api.dart';
import 'ffi/bindings.g.dart';

export 'ffi/bindings.g.dart' show OrtLoggingLevel;

import 'status.dart';

class OnnxEnv implements Finalizable {
  final Pointer<OrtEnv> envPtr;
  OnnxEnv._(this.envPtr);

  static OnnxEnv create(OrtLoggingLevel level, String logId) {
    final envPtr = () {
      final envPtrPtr = calloc<Pointer<OrtEnv>>();
      final logIdPtr = logId.toNativeUtf8().cast<Char>();
      try {
        ortApi.CreateEnv(level.value, logIdPtr, envPtrPtr).guard();
        return envPtrPtr.value;
      } finally {
        calloc.free(logIdPtr);
        calloc.free(envPtrPtr);
      }
    }();

    final obj = OnnxEnv._(envPtr);

    Gc.env.attach(obj, envPtr.cast(), detach: obj);

    return obj;
  }

  void dispose() => Gc.env.detach(this);
}
