import 'dart:io';

class Version implements Comparable<Version> {
  final int major;
  final int minor;
  final int patch;

  Version(this.major, this.minor, this.patch);

  factory Version.parse(String s) {
    final parts = s.split('.');
    if (parts.length != 3) throw FormatException('Invalid version: $s');
    return Version(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  Version operator +(dynamic other) => switch (other) {
    int n => Version(major, minor, patch + n),
    (int y, int z) => Version(major, minor + y, patch + z),
    (int x, int y, int z) => Version(major + x, minor + y, patch + z),
    Version v => Version(major + v.major, minor + v.minor, patch + v.patch),
    _ => throw ArgumentError('Can only add 1, 2, or 3 to Version'),
  };
  @override
  String toString() => '$major.$minor.$patch';

  static final RegExp pattern = RegExp(r'^\d+\.\d+\.\d+$');
  static bool isValid(String s) => pattern.hasMatch(s);
}

void checkVersion(String version, String pubspecPath, String pyprojectPath) {
  final pubspecContent = File(pubspecPath).readAsStringSync();
  final pyprojectContent = File(pyprojectPath).readAsStringSync();
  final pubspecVer = pubspecVersion(pubspecContent)?.toString();
  final pyprojectVer = pyprojectVersion(pyprojectContent)?.toString();
  if (pubspecVer != version) {
    print('WARNING: pubspec.yaml version is $pubspecVer, expected $version');
  }
  if (pyprojectVer != version) {
    print(
      'WARNING: pyproject.toml version is $pyprojectVer, expected $version',
    );
  }
  if (pubspecVer == version && pyprojectVer == version) {
    print('Version check passed: $version');
  }
}

Future<void> main(List<String> args) async {
  // Determine root directory
  final rootDir = args.isNotEmpty
      ? Directory(args[0])
      : File(Platform.script.toFilePath()).parent.parent;

  // Paths for version check
  final pubspecPath = '${rootDir.path}/dart/pubspec.yaml';
  final pyprojectPath = '${rootDir.path}/python/pyproject.toml';
  final pythonDir = Directory('${rootDir.path}/python');

  print('Root directory: ${rootDir.path}');

  // Expand han_dog_message/*.proto manually
  final protoDir = Directory('${rootDir.path}/han_dog_message');
  final protoFiles = protoDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.proto'))
      .map((f) => 'han_dog_message/${f.uri.pathSegments.last}')
      .toList();
  if (protoFiles.isEmpty) {
    print('No .proto files found in han_dog_message/.');
    exit(1);
  }

  // 1. Compile protos for Dart and Python
  print('Compiling protos...');
  await _run('protoc', [
    '--dart_out=grpc:dart/lib/',
    '-I',
    '.',
    ...protoFiles,
  ], cwd: rootDir);
  await _run('poetry', [
    'run',
    'python',
    '-m',
    'grpc_tools.protoc',
    '-I',
    '..',
    '--python_out=.',
    '--pyi_out=.',
    '--grpc_python_out=.',
    ...protoFiles.map((f) => '../$f'),
  ], cwd: pythonDir);
  print('Protos compiled.');

  // 2. Prompt for new version and update files
  // Read current versions
  final pubspecFile = File(pubspecPath);
  final pubspecContent = pubspecFile.readAsStringSync();
  final pyprojectFile = File(pyprojectPath);
  final pyprojectContent = pyprojectFile.readAsStringSync();

  final currentPubspecVer = pubspecVersion(pubspecContent);
  final currentPyprojectVer = pyprojectVersion(pyprojectContent);

  if (currentPubspecVer == null || currentPyprojectVer == null) {
    print('Could not find current version in pubspec.yaml or pyproject.toml.');
    exit(1);
  }

  if (currentPubspecVer.compareTo(currentPyprojectVer) != 0) {
    print(
      'Version mismatch: pubspec.yaml has $currentPubspecVer, pyproject.toml has $currentPyprojectVer',
    );
    exit(1);
  }

  final currentVersion = currentPubspecVer;

  Version? newVersion;
  final suggestedVersion = currentVersion + 1;
  while (true) {
    stdout.write(
      '\nCurrent version: $currentVersion\nEnter the new version (e.g., $suggestedVersion): ',
    );
    final input = stdin.readLineSync();
    if (input == null || input.isEmpty) {
      print('No version entered. Exiting.');
      exit(1);
    }
    if (!Version.isValid(input)) {
      print('Version must be in format x.y.z (e.g., $suggestedVersion)');
      continue;
    }
    final candidate = Version.parse(input);
    if (candidate.compareTo(currentVersion) <= 0) {
      print('Version must be greater than current version ($currentVersion)');
      continue;
    }
    newVersion = candidate;
    break;
  }
  final version = newVersion.toString();

  // Update pubspec.yaml
  final newPubspec = pubspecContent.replaceFirst(
    RegExp(r'version:\s*[^\n]+'),
    'version: $version',
  );
  pubspecFile.writeAsStringSync(newPubspec);

  // Update pyproject.toml
  final newPyproject = pyprojectContent.replaceFirst(
    RegExp(r'version\s*=\s*"[^"]+"'),
    'version = "$version"',
  );
  pyprojectFile.writeAsStringSync(newPyproject);

  print('Updated versions to $version in pubspec.yaml and pyproject.toml.');

  // Check versions
  checkVersion(version, pubspecPath, pyprojectPath);

  // 3. Create git tag and push
  final tag = 'v$version';
  await _run('git', ['add', '.'], cwd: rootDir);
  stdout.write('Enter commit message for version $version: ');
  final commitMessage = stdin.readLineSync() ?? '';
  await _run(
    'git',
    ['commit', '-m', '$version: $commitMessage'],
    allowFail: true,
    cwd: rootDir,
  );
  await _run('git', ['tag', tag], cwd: rootDir);
  await _run('git', ['push', 'origin', 'main', '--tags'], cwd: rootDir);

  print('\nPublish steps complete.');
}

Future<void> _run(
  String cmd,
  List<String> args, {
  bool allowFail = false,
  Directory? cwd,
}) async {
  final result = await Process.run(cmd, args, workingDirectory: cwd?.path);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0 && !allowFail) {
    print('Command failed: $cmd ${args.join(' ')}');
    exit(result.exitCode);
  }
}

Version? pubspecVersion(String content) {
  final match = RegExp(r'version:\s*([\d\.]+)').firstMatch(content);
  return match != null ? Version.parse(match.group(1)!) : null;
}

Version? pyprojectVersion(String content) {
  final match = RegExp(r'version\s*=\s*"([\d\.]+)"').firstMatch(content);
  return match != null ? Version.parse(match.group(1)!) : null;
}
