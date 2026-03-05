import 'package:pcan/pcan.dart';

void main() async {
  final (channel, status) = lookUpChannel("devicetype=PCAN_USB");
  if (status.isError) {
    print("Error looking up channel: $status");
    return;
  }

  final pcan = Pcan(channel);
  final result = pcan.open(.baud1M);
  if (result.isError) {
    print("Error initializing PCAN: $result");
    return;
  }

  print("PCAN initialized successfully on channel: $channel");

  // 测试是不是阻塞

  {
    while (true) {
      final (message, timestamp, status) = pcan.read();

      if (status == .ok || status == .qrcvempty) {
        print("Received message: $message at $timestamp");
      } else {
        print("Error reading message: $status");
      }

      await Future.delayed(Duration(milliseconds: 100)); // 避免过于频繁的读取
    }
  }
}
