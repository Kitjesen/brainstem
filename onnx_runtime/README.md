# onnx_runtime

## quick start

```dart
void main() async {
  final env = OnnxEnv.create(
    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
    'onnx_runtime_example',
  );

  final session = InferenceSession.create(
    env,
    await rootBundle.load('assets/add_one.onnx').buffer.asUint8List(),
  );

  final (outputNames, outputValues) = session.run({
    'x': OnnxFloat(value: [1], shape: [1]),
  });

  session.dispose();
  env.dispose();
}
```

## develop

参考代码

- [fonnx](https://github.com/Telosnex/fonnx)
- [onnxruntime_flutter](https://github.com/gtbluesky/onnxruntime_flutter)

设计想法:

比如对于 session_options, 我是通过来填充这个指针的内容, 不考虑 gc, 仅数据转化, 然后在其他地方考虑 gc

对于 info 也是, 就是读取

### native release

https://api.dart.dev/stable/2.18.5/dart-ffi/NativeFinalizer-class.html

```dart
final class Gc {
  static final env = ffi.NativeFinalizer(_api.ReleaseEnv.cast());
}

class OnnxEnv implements Finalizable {
  final Pointer<OrtEnv> envPtr;
  OnnxEnv._(this.envPtr);

  static OnnxEnv create(OrtLoggingLevel level) {
    final envPtr = ortApi.CreateEnv(level.value);
    final obj = OnnxEnv._(envPtr);

    Gc.env.attach(obj, envPtr.cast(), detach: obj);

    return obj;
  }

  void dispose() => Gc.env.detach(this);
}

```

Users can dispose the session and environment. If they forget, the finalizer will be called automatically when the Dart object is garbage collected.

## bug

锁定文件导致失败

```bash
if (Test-Path "c:\Users\Dz\Desktop\test\dog\onnx_runtime\example\build\flutter_assets\assets\policy.onnx") { Remove-Item "c:\Users\Dz\Desktop\test\dog\onnx_runtime\example\build\flutter_assets\assets\policy.onnx" -Force }
```
