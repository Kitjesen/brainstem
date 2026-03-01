import 'package:han_dog_message/han_dog_message.dart';

void main() {
  final command = Vector3()
    ..x = 1.0
    ..y = 2.0
    ..z = 3.0;

  final bytes = command.writeToBuffer();
  print('Serialized Command to bytes: $bytes');

  final deserializedCommand = Vector3.fromBuffer(bytes);
  print(
    'Deserialized Command from bytes: ${deserializedCommand.x}, ${deserializedCommand.y}, ${deserializedCommand.z}',
  );
}
