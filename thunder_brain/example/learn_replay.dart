import 'package:rxdart/rxdart.dart';

void main() {
  final pub = ReplaySubject<List<int>>(maxSize: 5);
  pub.stream.listen((e) => print(e));
  print('first time: ${pub.values}');
  for (int i = 0; i < 10; i++) {
    pub.add([i, i * i]);
    print(
      'after adding $i: ${pub.values}, [1:] ${pub.values.expand((o) => o).toList()}',
    );
  }
}
