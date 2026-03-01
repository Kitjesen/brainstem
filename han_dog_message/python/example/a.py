from han_dog_message.type_pb2 import Vector3


def main():
    # Create a Vector3 message
    command = Vector3()
    command.x = 1.0
    command.y = 2.0
    command.z = 3.0

    # Serialize to bytes
    bytes_out = command.SerializeToString()
    print(f"Serialized Command to bytes: {bytes_out}")

    # Deserialize from bytes
    deserialized_command = Vector3()
    deserialized_command.ParseFromString(bytes_out)
    print(
        f"Deserialized Command from bytes: {deserialized_command.x}, {deserialized_command.y}, {deserialized_command.z}"
    )


if __name__ == "__main__":
    main()
