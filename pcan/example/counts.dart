import 'package:pcan/pcan.dart';

void main() async {
  final (counts, _) = Pcan.counts;
  print('Total PCAN channels available: $counts');

  final (channels, _) = Pcan.getAttachedChannels(counts);
  for (var i = 0; i < counts; i++) {
    final channel = channels[i];
    print('Channel $i: $channel');
  }

  print('${Pcan(.usbbus1).condition}');
}
