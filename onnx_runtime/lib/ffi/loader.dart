import 'dart:ffi';
import 'dart:io';

/// The loaded dynamic library instance
final dylib = DynamicLibrary.open(() {
  return switch (Platform.operatingSystem) {
    'windows' => 'onnxruntime.dll',
    'linux' => 'libonnxruntime.so',
    // 'macos' => 'libonnxruntime.dylib',
    _ => throw UnsupportedError(
      'Unsupported platform: ${Platform.operatingSystem}',
    ),
  };
}());
