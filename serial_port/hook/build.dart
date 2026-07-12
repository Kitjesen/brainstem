import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

final Logger logger = Logger('serial_port hook');

Future<void> main(List<String> args) async {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(
      (record) => print(
        '[${record.level.name}] [${record.loggerName}] ${record.time}: ${record.message}',
      ),
    );

  await build(args, (input, output) async {
    final cserialPortDir = Directory.fromUri(
      input.packageRoot.resolve('src/CSerialPort/'),
    );
    if (!cserialPortDir.existsSync() &&
        !await fetchSubmodule(input.packageRoot.resolve('../'))) {
      throw Exception('Failed to fetch CSerialPort submodule.');
    }

    final dllPath = input.outputDirectory.resolve('bin').toFilePath();
    final builder = CMakeBuilder.create(
      name: input.packageName,
      sourceDir: input.packageRoot.resolve('src/CSerialPort/bindings/c/'),
      defines: {
        'CSERIALPORT_ENABLE_UTF8': 'ON',
        'CMAKE_BINARY_DIR': input.outputDirectory.toFilePath(),
        // Dynamic library outputs: place all configs into the same `bin` folder
        'CMAKE_RUNTIME_OUTPUT_DIRECTORY': dllPath,
        'CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG': dllPath,
        'CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE': dllPath,
        'CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO': dllPath,
        'CMAKE_RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL': dllPath,

        'CMAKE_LIBRARY_OUTPUT_DIRECTORY': dllPath,
        'CMAKE_LIBRARY_OUTPUT_DIRECTORY_DEBUG': dllPath,
        'CMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE': dllPath,
        'CMAKE_LIBRARY_OUTPUT_DIRECTORY_RELWITHDEBINFO': dllPath,
        'CMAKE_LIBRARY_OUTPUT_DIRECTORY_MINSIZEREL': dllPath,
      },
      logger: logger,
    );
    await builder.run(input: input, output: output, logger: logger);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/cserialport.g.dart',
        file: input.outputDirectory.resolve(
          switch (input.config.code.targetOS) {
            .linux => 'bin/libcserialport.so',
            .macOS => 'bin/libcserialport.dylib',
            .windows => 'bin/cserialport.dll',
            _ => throw UnsupportedError(
              'Unsupported OS: ${input.config.code.targetOS}',
            ),
          },
        ),
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

Future<bool> fetchSubmodule(Uri repoUri) async {
  final repoDir = Directory.fromUri(repoUri);
  final path = repoDir.path;

  logger.info('Checking for submodule at $path');

  if (await submoduleExists(path)) {
    logger.info('Submodule already exists at $path');
    return true;
  }

  logger.info('Fetching submodule at $path');
  final result = await Process.run('git', [
    'submodule',
    'update',
    '--init',
    '--recursive',
  ], workingDirectory: path);

  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      ['submodule', 'update', '--init', '--recursive'],
      'Failed to fetch $path: ${result.stderr}',
      result.exitCode,
    );
  }
  return await submoduleExists(path);
}

Future<bool> submoduleExists(String path) async {
  // Run `git submodule status`, read result
  final result = await Process.run('git', [
    'submodule',
    'status',
  ], workingDirectory: path);

  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      ['submodule', 'status'],
      'Failed to check $path: ${result.stderr}',
      result.exitCode,
    );
  }

  final output = result.stdout.toString().trim();
  if (output.isEmpty) return false;

  return output.split('\n').any((line) {
    final fields = line.trimLeft().split(RegExp(r'\s+'));
    return fields.length > 1 && fields[1] == 'serial_port/src/CSerialPort';
  });
}
