import 'package:pcan/pcan.dart';

void main() {
  final message = PcanMessage(
    id: 305,
    type: .standard,
    data: .fromList([1, 2, 3, 4, 5]),
  );
  print('Hexadecimal Representation: $message');
}
