// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.config.buildCodeAssets) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'src/pcan_basic.g.dart',
          linkMode: DynamicLoadingSystem(switch (input.config.code.targetOS) {
            .linux => .file('libpcanbasic.so'),
            .windows => .file('PCANBasic.dll'),
            final os => throw UnsupportedError('Unsupported OS: ${os.name}.'),
          }),
        ),
      );
    }
  });
}
