## setup

见 [README](../../README.md#setup) 说明

## install

```yaml
dependencies:
  pcan:
    git:
      url: https://github.com/QiongPei/pcan
      path: dart/pcan
      tag_pattern: v{{version}}
    version: ^1.0.0
```

## quick start

```dart
import 'package:pcan/pcan.dart';

void main() async {
  final (channel, status) = lookUpChannel("devicetype=PCAN_USB");
  if (status.isError) {
    print("Error looking up channel: $status");
    return;
  }

  final pcan = Pcan(channel);
  final result = pcan.initialize(PCANBaudRate.baud1M);
  if (result.isError) {
    print("Error initializing PCAN: $result");
    return;
  }

  {
    while (true) {
      final (status, message, timestamp) = pcan.read();

      if (status == PCANStatus.ok || status == PCANStatus.qrcvempty) {
        print("Received message: $message at $timestamp");
      } else {
        print("Error reading message: $status");
      }

      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}
```

## develop

generated:

```bash
dart run tool/ffigen.dart 
```