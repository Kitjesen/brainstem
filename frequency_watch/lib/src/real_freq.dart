import 'dart:async';

class RealFrequency {
  static final manager = _Manager();

  RealFrequency() {
    manager.register(this);
  }

  int _count = 0;
  int _value = 0;
  int get value => _value;

  void add(int n) {
    _count += n;
  }

  RealFrequency operator +(int n) {
    add(n);
    return this;
  }

  void dispose() {
    manager.unregister(this);
  }
}

class _Manager {
  final Map<RealFrequency, RealFrequency> _frequencies = {};

  final _controller = StreamController<void>.broadcast();
  Stream<void> get onTick => _controller.stream;

  Timer? _timer;

  void register(RealFrequency freq) {
    _frequencies[freq] = freq;
  }

  void unregister(RealFrequency freq) {
    _frequencies.remove(freq);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _frequencies.clear();
    _controller.close();
  }

  void watch() {
    if (_timer != null) return;
    _timer = Timer.periodic(const .new(seconds: 1), (t) {
      _controller.add(null);
      for (final freq in _frequencies.values) {
        freq._value = freq._count;
        freq._count = 0;
      }
    });
  }
}
