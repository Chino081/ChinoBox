import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../features/settings/app_settings.dart';
import '../app_error.dart';
import '../logging/app_logger.dart';

class MoviesHttpClient {
  MoviesHttpClient(this.settings) {
    final proxy = _proxyFromSettings(settings);
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 24),
        sendTimeout: const Duration(seconds: 12),
        followRedirects: true,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
        responseType: ResponseType.plain,
      ),
    );
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => _createClient(proxy),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final cookie = _cookieHeader(options.uri);
          if (cookie.isNotEmpty) {
            final existing =
                options.headers[HttpHeaders.cookieHeader]?.toString() ?? '';
            options.headers[HttpHeaders.cookieHeader] = [
              if (existing.isNotEmpty) existing,
              cookie,
            ].join('; ');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          _storeCookies(response);
          handler.next(response);
        },
      ),
    );
  }

  late final Dio _dio;
  final AppSettings settings;
  final _cookiesByHost = <String, Map<String, Cookie>>{};

  Future<String> getText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return _requestText(
        () => _dio.get<String>(url, options: _options(headers)));
  }

  Future<Uint8List> getBytes(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: _options(headers, responseType: ResponseType.bytes),
        );
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 200 && statusCode < 400) {
          return Uint8List.fromList(response.data ?? const []);
        }
        throw AppError('服务器返回 $statusCode');
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
    AppLogger.warn('网络请求失败：${lastError.runtimeType}');
    throw AppError('网络请求失败，请检查网络或代理设置', cause: lastError);
  }

  Future<String> postForm(
    String url,
    Map<String, String> form, {
    Map<String, String> headers = const {},
  }) async {
    return _requestText(
      () => _dio.post<String>(
        url,
        data: form,
        options: _options(
          headers,
          contentType: Headers.formUrlEncodedContentType,
        ),
      ),
    );
  }

  Options _options(
    Map<String, String> headers, {
    String? contentType,
    ResponseType? responseType,
  }) {
    return Options(
      headers: headers.isEmpty ? null : headers,
      contentType: contentType,
      responseType: responseType,
    );
  }

  Future<String> _requestText(Future<Response<String>> Function() run) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await run();
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 200 && statusCode < 400) {
          return response.data ?? '';
        }
        throw AppError('服务器返回 $statusCode');
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
    AppLogger.warn('网络请求失败：${lastError.runtimeType}');
    throw AppError('网络请求失败，请检查网络或代理设置', cause: lastError);
  }

  HttpClient _createClient(Uri? proxy) {
    final client = HttpClient();
    if (proxy == null) return client;

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
          parts.length > 1 ? parts.sublist(1).join(':') : '');
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
    return client;
  }

  String _cookieHeader(Uri uri) {
    final values = <String>[];
    for (final entry in _cookiesByHost.entries) {
      if (uri.host == entry.key || uri.host.endsWith('.${entry.key}')) {
        values.addAll(entry.value.values.map((cookie) {
          return '${cookie.name}=${cookie.value}';
        }));
      }
    }
    return values.join('; ');
  }

  void _storeCookies(Response<dynamic> response) {
    final values = response.headers[HttpHeaders.setCookieHeader];
    if (values == null || values.isEmpty) return;
    final fallbackHost = response.realUri.host;
    for (final value in values) {
      Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(value);
      } catch (_) {
        continue;
      }
      final host = (cookie.domain?.trim().isNotEmpty ?? false)
          ? cookie.domain!.replaceFirst(RegExp(r'^\.'), '')
          : fallbackHost;
      _cookiesByHost.putIfAbsent(host, () => {})[cookie.name] = cookie;
    }
  }
}

Uri? _proxyFromSettings(AppSettings settings) {
  final value = settings.proxy.trim().isNotEmpty
      ? settings.proxy.trim()
      : Platform.environment['MOVIESBOX_PROXY']?.trim() ?? '';
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' &&
      uri.scheme != 'https' &&
      uri.scheme != 'socks5' &&
      uri.scheme != 'socks4') {
    return null;
  }
  return uri;
}
