import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;

/// gRPC server credentials that trust only the configured LingTu client CA.
final class MutualTlsServerCredentials extends grpc.ServerTlsCredentials {
  final SecurityContext _context;

  MutualTlsServerCredentials({
    required String certificateFile,
    required String privateKeyFile,
    required String clientCaFile,
  }) : _context = grpc.createSecurityContext(true),
       super() {
    _context
      ..useCertificateChain(certificateFile)
      ..usePrivateKey(privateKeyFile)
      ..setTrustedCertificates(clientCaFile);
  }

  @override
  SecurityContext get securityContext => _context;
}
