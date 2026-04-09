from han_dog_message import type_pb2


def main():
    # Create a Matrix4 message and set elements
    m = type_pb2.Matrix4()
    m.values.extend(float(i) for i in range(16))

    # Serialize to bytes
    bytes_data = m.SerializeToString()
    print(f"Serialized Matrix4 to bytes: {list(bytes_data)}")

    # Deserialize from bytes
    deserialized_matrix = type_pb2.Matrix4()
    deserialized_matrix.ParseFromString(bytes_data)
    print(f"Deserialized Matrix4 from bytes: {deserialized_matrix}")


if __name__ == "__main__":
    main()
