import 'dart:io';

/// Applies proxy configuration to an [HttpClient].
///
/// If [proxy] is null, the client is returned unmodified.
void applyProxyToClient(HttpClient client, Uri? proxy) {
  if (proxy == null) return;

  final scheme = proxy.scheme.toLowerCase();
  final host = proxy.host;
  final port =
      proxy.hasPort ? proxy.port : (scheme.startsWith('socks') ? 1080 : 8080);

  client.findProxy = (uri) {
    if (scheme.startsWith('socks')) {
      return 'SOCKS $host:$port';
    }
    return 'PROXY $host:$port';
  };

  if (proxy.userInfo.isNotEmpty) {
    final parts = proxy.userInfo.split(':');
    final user = Uri.decodeComponent(parts.first);
    final password = Uri.decodeComponent(
      parts.length > 1 ? parts.sublist(1).join(':') : '',
    );
    client.authenticateProxy = (
      String host,
      int port,
      String scheme,
      String? realm,
    ) async {
      client.addProxyCredentials(
        host,
        port,
        realm ?? '',
        HttpClientBasicCredentials(user, password),
      );
      return true;
    };
  }
}
