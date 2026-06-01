import 'dart:async';
import 'dart:io';

class PlaybackProxy {
  PlaybackProxy._();

  static final PlaybackProxy instance = PlaybackProxy._();

  HttpServer? _server;
  var _nextId = 0;
  final _entries = <String, _ProxyEntry>{};

  Future<String> proxiedUrl(
    String targetUrl,
    Map<String, String> headers,
  ) async {
    final server = await _ensureServer();
    final token = (++_nextId).toRadixString(36);
    final targetUri = Uri.parse(targetUrl);
    final name = targetUri.pathSegments.isEmpty
        ? 'media.mp4'
        : targetUri.pathSegments.last;
    _entries[token] = _ProxyEntry(targetUrl, Map.of(headers));
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [token, name.isEmpty ? 'media.mp4' : name],
    ).toString();
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(server.forEach(_handle));
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final token =
        request.uri.pathSegments.isEmpty ? '' : request.uri.pathSegments.first;
    final entry = _entries[token];
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final upstream =
          await client.openUrl(request.method, Uri.parse(entry.url));
      upstream.followRedirects = true;
      upstream.headers.set(HttpHeaders.acceptHeader, '*/*');
      for (final header in entry.headers.entries) {
        if (_blockedHeaderNames.contains(header.key.toLowerCase())) continue;
        upstream.headers.set(header.key, header.value);
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        upstream.headers.set(HttpHeaders.rangeHeader, range);
      }
      final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
      if (ifRange != null && ifRange.isNotEmpty) {
        upstream.headers.set(HttpHeaders.ifRangeHeader, ifRange);
      }

      final upstreamResponse = await upstream.close();
      request.response.statusCode = upstreamResponse.statusCode;
      if (upstreamResponse.contentLength >= 0) {
        request.response.contentLength = upstreamResponse.contentLength;
      }
      _copyHeader(
          upstreamResponse, request.response, HttpHeaders.contentTypeHeader);
      _copyHeader(
          upstreamResponse, request.response, HttpHeaders.contentRangeHeader);
      _copyHeader(
          upstreamResponse, request.response, HttpHeaders.acceptRangesHeader);
      _copyHeader(upstreamResponse, request.response, HttpHeaders.etagHeader);
      _copyHeader(
          upstreamResponse, request.response, HttpHeaders.lastModifiedHeader);
      _copyHeader(
          upstreamResponse, request.response, HttpHeaders.cacheControlHeader);

      if (request.method == 'HEAD') {
        await request.response.close();
      } else {
        await upstreamResponse.pipe(request.response);
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {
        // The response may already be closed if the upstream stream failed.
      }
    } finally {
      client.close(force: true);
    }
  }

  void _copyHeader(
    HttpClientResponse from,
    HttpResponse to,
    String name,
  ) {
    final values = from.headers[name];
    if (values == null || values.isEmpty) return;
    to.headers.set(name, values);
  }
}

const _blockedHeaderNames = {
  'connection',
  'content-length',
  'host',
  'if-range',
  'range',
  'transfer-encoding',
};

class _ProxyEntry {
  const _ProxyEntry(this.url, this.headers);

  final String url;
  final Map<String, String> headers;
}
