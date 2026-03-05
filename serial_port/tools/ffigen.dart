import 'dart:io';

import 'package:ffigen/ffigen.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');
  FfiGenerator(
    output: .new(dartFile: packageRoot.resolve('lib/src/cserialport.g.dart')),
    headers: .new(
      entryPoints: [
        packageRoot.resolve('src/CSerialPort/bindings/c/cserialport.h'),
      ],
      include: (header) => header.path.endsWith('cserialport.h'), // 只导出这个文件的接口
    ),
    macros: .includeAll,
    structs: .includeAll,
    functions: .includeAll,
    typedefs: .includeAll,
  ).generate();
}
