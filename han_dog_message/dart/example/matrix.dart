import 'package:han_dog_message/han_dog_message.dart';

void main() {
  final m = Matrix4(values: List.generate(16, (i) => i.toDouble()));

  final bytes = m.writeToBuffer();
  print('Serialized Matrix4 to bytes: $bytes');

  final deserializedMatrix = Matrix4.fromBuffer(bytes);
  print('Deserialized Matrix4 from bytes: $deserializedMatrix');
}
