import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'cserialport.g.dart';

class SerialPortInfo {
  final String name;
  final String description;
  final String hardwareId;

  const SerialPortInfo({
    this.name = '',
    this.description = '',
    this.hardwareId = '',
  });

  @override
  String toString() =>
      'name: $name, description: $description, id: $hardwareId';
}

List<SerialPortInfo> getPortInfos() {
  final portInfoArray = calloc<SerialPortInfoArray>();

  try {
    CSerialPortAvailablePortInfosMalloc(portInfoArray);

    final size = portInfoArray.ref.size;
    if (size == 0 || portInfoArray.ref.portInfo == ffi.nullptr) return [];

    return .generate(
      size,
      (index) => .new(
        name: portInfoArray.ref.portInfo[index].portName.toDartString(),
        description: portInfoArray.ref.portInfo[index].description
            .toDartString(),
        hardwareId: portInfoArray.ref.portInfo[index].hardwareId.toDartString(),
      ),
    );
  } finally {
    CSerialPortAvailablePortInfosFree(portInfoArray);
    calloc.free(portInfoArray);
  }
}

/// https://github.com/aeb-dev/steamworks/issues/6
extension on ffi.Array<ffi.Char> {
  String toDartString() =>
      utf8.decode([for (int index = 0; this[index] != 0; index++) this[index]]);
}
