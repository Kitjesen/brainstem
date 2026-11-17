import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// This adapter deliberately refuses other observation/action contracts.
class RecoveryModelSpec {
  static const supportedContract = 'mujica-v89-history60x6-raw16-features56';
  final String modelPath;
  final String sha;
  RecoveryModelSpec._(this.modelPath, this.sha);

  static RecoveryModelSpec parse(Object? value, {required Uri configUri}) {
    if (value is! Map ||
        value['contract'] != supportedContract ||
        value['schema_version'] != 1) {
      throw FormatException('Unsupported Recovery model contract');
    }
    final path = value['model'];
    final sha = value['sha256'];
    if (path is! String ||
        path.trim() != path ||
        path.isEmpty ||
        path.contains(RegExp(r'[\r\n]')) ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw FormatException('Invalid Recovery model path/SHA256');
    }
    final resolved = configUri.resolve(path);
    if (resolved.scheme != 'file') {
      throw FormatException('Local model file required');
    }
    return RecoveryModelSpec._(resolved.toFilePath(), sha);
  }

  static Future<RecoveryModelSpec> load(String path) async {
    final file = File(path).absolute;
    return parse(jsonDecode(await file.readAsString()), configUri: file.uri);
  }

  Future<void> verify() async {
    if (sha256.convert(await File(modelPath).readAsBytes()).toString() != sha) {
      throw StateError('Recovery model SHA256 mismatch');
    }
  }
}
