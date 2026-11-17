import 'dart:io';

import 'package:grpc/grpc.dart';

bool isPrivateLanIpv4(String value) {
  if (!RegExp(
    r'^(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}$',
  ).hasMatch(value)) {
    return false;
  }
  final parts = value.split('.').map(int.parse).toList(growable: false);
  if (parts.any((part) => part > 255)) return false;
  return parts[0] == 10 ||
      (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] == 192 && parts[1] == 168);
}

List<String> grpcLanDevelopmentConfigurationErrors({
  required String transport,
  required String address,
  required Set<String> peers,
}) {
  if (transport != 'mtls' && transport != 'lan-dev') {
    return ['THUNDER_GRPC_TRANSPORT must be mtls or lan-dev'];
  }
  if (transport != 'lan-dev') return const [];
  return [
    if (!isPrivateLanIpv4(address))
      'THUNDER_GRPC_LAN_ADDRESS must be a canonical private IPv4 address',
    if (peers.isEmpty || peers.any((peer) => !isPrivateLanIpv4(peer)))
      'LAN development requires non-empty exact private IPv4 allowed peers',
  ];
}

bool _allowedLanPeer(ServiceCall call, Set<String> allowedPeers) {
  final remote = call.remoteAddress;
  return remote != null &&
      remote.type == InternetAddressType.IPv4 &&
      isPrivateLanIpv4(remote.address) &&
      allowedPeers.contains(remote.address);
}

Interceptor lanDevelopmentPeerInterceptor(Set<String> allowedPeers) {
  final peers = Set<String>.unmodifiable(allowedPeers);
  return (call, method) => _allowedLanPeer(call, peers)
      ? null
      : GrpcError.permissionDenied('Source is not allowed for LAN development');
}

/// A development session label, never a cryptographic identity or secret.
String? lanDevelopmentPrincipal(ServiceCall call, Set<String> allowedPeers) {
  if (!_allowedLanPeer(call, allowedPeers)) return null;
  final principal = call.clientMetadata?['x-doso-dev-client'];
  return principal != null &&
          RegExp(r'^lan-[0-9a-f]{32}@dev$').hasMatch(principal)
      ? principal
      : null;
}
