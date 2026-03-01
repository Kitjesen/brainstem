import 'package:frequency_watch/frequency_watch.dart';

void main() async {
  final freq = RealFrequency();
  RealFrequency.manager.watch();
  RealFrequency.manager.onTick.listen((_) {
    print('Frequency value: ${freq.value}');
  });

  // Stream.periodic(
  //   const Duration(milliseconds: 10),
  //   (count) => count,
  // ).take(1000).listen((count) {
  //   freq.add(1);
  // });

  await for (final _ in Stream.periodic(
    const Duration(milliseconds: 10),
    (count) => count,
  ).take(1000)) {
    freq.add(1);
  }
  await Future.delayed(const Duration(seconds: 1));
  RealFrequency.manager.dispose();
}
