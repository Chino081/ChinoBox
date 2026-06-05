import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../features/settings/app_settings.dart';
import '../app_error.dart';
import '../logging/app_logger.dart';
import 'proxy_helper.dart';

class MoviesHttpClient {
  MoviesHttpClient(this.settings, {this.noProxy = false}) {
    final proxy = noProxy ? null : proxyFromSettings(settings);
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
          final parts = <String>[
            if (cookie.isNotEmpty) cookie,
            if (_funCdnToken.isNotEmpty) '_funcdn_token=$_funCdnToken',
          ];
          if (parts.isNotEmpty) {
            final existing =
                options.headers[HttpHeaders.cookieHeader]?.toString() ?? '';
            options.headers[HttpHeaders.cookieHeader] = [
              if (existing.isNotEmpty) existing,
              ...parts,
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
  final bool noProxy;
  final _cookiesByHost = <String, Map<String, Cookie>>{};

  Future<String> getText(
    String url, {
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
  }) async {
    return _requestText(() => _dio.get<String>(
          url,
          options: _options(headers),
          cancelToken: cancelToken,
        ));
  }

  Future<Uint8List> getBytes(
    String url, {
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final response = await _retryRequest(
      () => _dio.get<List<int>>(
        url,
        options: _options(headers, responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      ),
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  Future<String> postForm(
    String url,
    Map<String, String> form, {
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
  }) async {
    return _requestText(
      () => _dio.post<String>(
        url,
        data: form,
        options: _options(
          headers,
          contentType: Headers.formUrlEncodedContentType,
        ),
        cancelToken: cancelToken,
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

  Future<Response<T>> _retryRequest<T>(
    Future<Response<T>> Function() run,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await run();
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 200 && statusCode < 400) {
          return response;
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

  Future<String> _requestText(Future<Response<String>> Function() run) async {
    final response = await _retryRequest(run);
    final body = response.data ?? '';
    if (_isFunCdnChallenge(body)) {
      final solved = await _solveFunCdnChallenge(body);
      if (solved) {
        final retryResponse = await _retryRequest(run);
        return retryResponse.data ?? '';
      }
    }
    return body;
  }

  bool _isFunCdnChallenge(String body) {
    return body.contains('jsCaptchaVerify') && body.contains('_funcdn_token');
  }

  Future<bool> _solveFunCdnChallenge(String body) async {
    final challenge = _extractCdnField(body, 'challenge');
    final answer = _extractCdnField(body, 'answer');
    final userinfo = _extractCdnField(body, 'userinfo');
    final hostinfo = _extractCdnField(body, 'hostinfo');
    if (challenge.isEmpty || answer.isEmpty) return false;

    // Brute-force 6-digit code: md5(challenge + code) == answer
    String? code;
    for (var i = 100000; i <= 999999; i++) {
      final hash = md5.convert(utf8.encode('$challenge$i')).toString();
      if (hash == answer) {
        code = i.toString();
        break;
      }
    }
    if (code == null) {
      AppLogger.warn('FunCDN challenge solve failed: no matching code');
      return false;
    }

    try {
      final verifyDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          },
        ),
      );
      final verifyResponse = await verifyDio.post<Map<String, dynamic>>(
        'https://fn-captcha.tacool.com/jsCaptchaVerify',
        data: {
          'userinfo': userinfo,
          'hostinfo': hostinfo,
          'challenge': challenge,
          'answer': answer,
          'code': code,
        },
      );
      final token = verifyResponse.data?['fc_token']?.toString();
      if (token == null || token.isEmpty) {
        AppLogger.warn('FunCDN verify returned no token');
        return false;
      }

      _funCdnToken = token;
      AppLogger.info('FunCDN challenge solved');
      return true;
    } catch (e) {
      AppLogger.warn('FunCDN verify request failed: $e');
      return false;
    }
  }

  String _funCdnToken = '';

  String _extractCdnField(String body, String field) {
    final match = RegExp("$field\\s*:\\s*['\"]([^'\"]+)['\"]").firstMatch(body);
    return match?.group(1) ?? '';
  }

  HttpClient _createClient(Uri? proxy) {
    final client = HttpClient();
    applyProxyToClient(client, proxy);
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
      } catch (e) {
        AppLogger.warn('Cookie 解析失败: $e');
        continue;
      }
      final host = (cookie.domain?.trim().isNotEmpty ?? false)
          ? cookie.domain!.replaceFirst(RegExp(r'^\.'), '')
          : fallbackHost;
      _cookiesByHost.putIfAbsent(host, () => {})[cookie.name] = cookie;
    }
  }
}

/// Resolved proxy URI from settings or environment.
Uri? proxyFromSettings(AppSettings settings) {
  final value = settings.proxy.trim().isNotEmpty
      ? settings.proxy.trim()
      : Platform.environment['MOVIESBOX_PROXY']?.trim() ?? '';
  if (value.isEmpty) return null;
  // Auto-prefix bare host:port with socks5:// as a sensible default.
  final normalized = value.contains('://') ? value : 'socks5://$value';
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' &&
      uri.scheme != 'https' &&
      uri.scheme != 'socks5' &&
      uri.scheme != 'socks4') {
    return null;
  }
  return uri;
}
