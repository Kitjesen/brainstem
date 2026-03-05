import 'dart:io';

import 'package:ffigen/ffigen.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');
  FfiGenerator(
    // Required. Output path for the generated bindings.
    output: Output(dartFile: packageRoot.resolve('lib/src/pcan_basic.g.dart')),
    // Optional. Where to look for header files.
    headers: Headers(
      entryPoints: [packageRoot.resolve('src/pcan.h')],
      include: (header) => header.path.endsWith('PCANBasic.h'), // 只导出这个文件的接口
    ),
    macros: Macros.includeAll,
    structs: Structs.includeAll,
    functions: Functions.includeAll,
  ).generate();
}
