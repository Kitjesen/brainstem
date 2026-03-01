part of 'onnx_api.dart';

final class Gc {
  static final env = ffi.NativeFinalizer(_api.ReleaseEnv.cast());
  static final session = ffi.NativeFinalizer(_api.ReleaseSession.cast());
}
