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

  static const _ignoredSuffixes = [
    'google.com',
    'googleapis.com',
    'gstatic.com',
    'googlesyndication.com',
    'googletagmanager.com',
    'google-analytics.com',
    'github.com',
    'githubusercontent.com',
    'youtube.com',
    'youtu.be',
    'twitter.com',
    'x.com',
    'facebook.com',
    'fbcdn.net',
    'instagram.com',
    'cloudflare.com',
    'cdnjs.cloudflare.com',
    'jquery.com',
    'bootstrapcdn.com',
    't.me',
    'telegram.org',
    'apple.com',
    'microsoft.com',
    'bing.com',
    'baidu.com',
    'bdstatic.com',
    'qq.com',
    'qpic.cn',
    'weibo.com',
    'zhihu.com',
    'douyin.com',
    'bilibili.com',
    'iqiyi.com',
    'youku.com',
    'sohu.com',
    'sina.com',
    'weibo.cn',
    '163.com',
    '126.net',
    'taobao.com',
    'tmall.com',
    'jd.com',
    'alipay.com',
    'alicdn.com',
    'amazon.com',
    'amazonaws.com',
    'azure.com',
    'wordpress.com',
    'wix.com',
    'godaddy.com',
    'vercel.app',
    'netlify.app',
    'pages.dev',
    'recaptcha.net',
    'gstatic.com',
    'doubleclick.net',
    'adsense.google.com',
  ];

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

    // Only extract URLs from <a href="..."> tags, not from the entire HTML
    final hrefPattern = RegExp(r"""<a\s[^>]*href=["']([^"']+)["']""", caseSensitive: false);
    final seen = <String>{};

    for (final match in hrefPattern.allMatches(html)) {
      final href = match.group(1)!;
      if (!href.startsWith('http')) continue;

      final uri = Uri.tryParse(href);
      if (uri == null || uri.host.isEmpty) continue;

      final host = uri.host.toLowerCase();

      if (seen.contains(host)) continue;
      seen.add(host);

      // Skip the release page itself and the current default domain
      if (host == releaseHost || host == defaultHost) continue;
      if (_isIgnoredDomain(host)) continue;

      // Skip if it looks like a CDN or resource host
      if (_looksLikeCdn(host)) continue;

      // Return the scheme + host as the new domain
      return '${uri.scheme}://$host';
    }

    return null;
  }

  bool _isIgnoredDomain(String host) {
    for (final suffix in _ignoredSuffixes) {
      if (host == suffix || host.endsWith('.$suffix')) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeCdn(String host) {
    // Skip hosts that look like CDNs or static resource servers
    final h = host.toLowerCase();
    if (h.startsWith('cdn.') || h.startsWith('static.') || h.startsWith('img.')) {
      return true;
    }
    if (h.contains('cdn') || h.contains('static') || h.contains('assets')) {
      return true;
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
