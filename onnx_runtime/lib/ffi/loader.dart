import 'dart:ffi';
import 'dart:io';

/// The loaded dynamic library instance
final dylib = DynamicLibrary.open(() {
  final explicitPath = Platform.environment['ONNXRUNTIME_DLL_PATH'];
  if (explicitPath != null && explicitPath.isNotEmpty) {
    return explicitPath;
  }
  return switch (Platform.operatingSystem) {
    'windows' => 'onnxruntime.dll',
    'linux' => 'libonnxruntime.so',
    // 'macos' => 'libonnxruntime.dylib',
    _ => throw UnsupportedError(
      'Unsupported platform: ${Platform.operatingSystem}',
    ),
  };
}());
