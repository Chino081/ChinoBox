import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/movies_http_client.dart';
import '../../../core/storage/local_store.dart';
import '../../settings/app_settings.dart';
import '../domain/media_source.dart';

class DomainResolver {
  DomainResolver._();

  static final instance = DomainResolver._();

  static const _cachePrefix = 'moviesbox.domain.';
  static const _cacheDuration = Duration(hours: 24);

  final _client = MoviesHttpClient(AppSettings.defaults(), noProxy: true);

  static const _ignoredDomains = {
    'google.com',
    'googleapis.com',
    'gstatic.com',
    'github.com',
    'githubusercontent.com',
    'youtube.com',
    'youtu.be',
    'twitter.com',
    'x.com',
    'facebook.com',
    'instagram.com',
    'cloudflare.com',
    'jquery.com',
    'bootstrapcdn.com',
    'cdnjs.cloudflare.com',
    'cdn.',
    'fonts.googleapis.com',
    'fonts.gstatic.com',
    't.me',
    'telegram.org',
    'apple.com',
    'microsoft.com',
    'bing.com',
    'baidu.com',
    'qq.com',
    'weibo.com',
    'zhihu.com',
    'douyin.com',
    'bilibili.com',
    'iqiyi.com',
    'youku.com',
    'sohu.com',
    'sina.com',
    '163.com',
    'taobao.com',
    'tmall.com',
    'jd.com',
    'alipay.com',
    'weixin.qq.com',
  };

  Future<void> checkAll(
    List<MediaSource> sources,
    AppSettings settings,
  ) async {
    for (final source in sources) {
      if (!source.hasReleasePage) continue;
      try {
        await fetchLatestDomain(source, settings);
      } catch (_) {
        // silent
      }
    }
  }

  Future<String?> fetchLatestDomain(
    MediaSource source,
    AppSettings settings,
  ) async {
    if (!source.hasReleasePage) return null;

    final cached = await _readCache(source.id);
    if (cached != null) return cached;

    try {
      final html = await _client.getText(
        source.releasePage,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
        },
      );
      final domain = _extractDomain(html, source);
      if (domain != null) {
        await _writeCache(source.id, domain);
        AppLogger.info('域名自动更新: ${source.name} -> $domain');
        return domain;
      }
    } catch (e) {
      AppLogger.warn('域名更新失败 ${source.name}: $e');
    }
    return null;
  }

  String? _extractDomain(String html, MediaSource source) {
    final releaseHost = Uri.tryParse(source.releasePage)?.host ?? '';
    final defaultHost = Uri.tryParse(source.defaultDomain)?.host ?? '';

    final urlPattern = RegExp(r'https?://([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})');
    final seen = <String>{};

    for (final match in urlPattern.allMatches(html)) {
      final url = match.group(0)!;
      final host = match.group(1)!.toLowerCase();

      if (seen.contains(host)) continue;
      seen.add(host);

      if (host == releaseHost || host == defaultHost) continue;
      if (_isIgnoredDomain(host)) continue;

      // Must look like a real site domain (has at least one subdomain or is short)
      final parts = host.split('.');
      if (parts.length < 2) continue;

      return url;
    }
    return null;
  }

  bool _isIgnoredDomain(String host) {
    for (final ignored in _ignoredDomains) {
      if (ignored.endsWith('.')) {
        if (host.startsWith(ignored) || host == ignored.substring(0, ignored.length - 1)) {
          return true;
        }
      } else if (host == ignored || host.endsWith('.$ignored')) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _readCache(String sourceId) async {
    final key = '$_cachePrefix$sourceId';
    final raw = await LocalStore.instance.readCache(key, _cacheDuration);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json['domain'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String sourceId, String domain) async {
    final key = '$_cachePrefix$sourceId';
    await LocalStore.instance.writeCache(key, jsonEncode({'domain': domain}));
  }
}
