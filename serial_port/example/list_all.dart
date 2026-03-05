import 'package:serial_port/serial_port.dart';

void main() {
  final ports = getPortInfos();

  for (final port in ports) {
    print(port);
  }
}
