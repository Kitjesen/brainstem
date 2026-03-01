<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages). 
-->

频率监测

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

```dart
import 'package:frequency_watch/frequency_watch.dart';

void main() {
  final watcher = FrequencyWatch(windowSize: 100);

  const duration = Duration(milliseconds: 1);
  Timer.periodic(duration, (timer) {
    watcher.watch();  // watch event

    final frequency = watcher.analyze(); // analyze frequency
  });
}
```

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder. 

```dart
const like = 'sample';
```

## Additional information

在Windows上的测试

```txt
=== Frequency Analysis (100 events) ===
Interval (µs): min = 52, median = 15386, p95 = 16142, max = 17408
Average interval: 14478 µs
Estimated frequency: median = 64.99 Hz, 
                     p95 = 61.95 Hz, 
                     avg = 69.07 Hz
```

应该每次计算的时候, 用当前时间来计算. 这个不会随着当前时间滑动, 如果 watch 不工作了, 那么时间流逝, 它也检测不到
