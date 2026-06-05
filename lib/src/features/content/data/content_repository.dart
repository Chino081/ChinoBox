import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../core/app_error.dart';
import '../../../core/network/movies_http_client.dart';
import '../../../core/storage/local_store.dart';
import '../../settings/app_settings.dart';
import '../../settings/settings_controller.dart';
import '../domain/content_models.dart';
import 'parser_registry.dart';
import 'site_parser.dart';

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  return ContentRepository(ref: ref, store: LocalStore.instance);
});

class ContentRepository {
  ContentRepository({
    required this.ref,
    required this.store,
  });

  final Ref ref;
  final LocalStore store;

  AppSettings get _settings => ref.read(settingsControllerProvider);

  MoviesHttpClient? _client;
  MoviesHttpClient? _directClient;
  String? _lastProxy;

  MoviesHttpClient get client {
    final proxy = proxyFromSettings(_settings);
    final proxyKey = proxy?.toString() ?? '';
    if (_client == null || _lastProxy != proxyKey) {
      _client = MoviesHttpClient(_settings);
      _lastProxy = proxyKey;
    }
    return _client!;
  }

  MoviesHttpClient get _direct {
    _directClient ??= MoviesHttpClient(_settings, noProxy: true);
    return _directClient!;
  }

  MoviesHttpClient clientFor(SiteParser parser) =>
      parser.needsProxy ? client : _direct;

  SiteParser parserFor([String? sourceId]) {
    return ParserRegistry.byId(sourceId ?? _settings.sourceId);
  }

  Future<HomePayload> home([String? sourceId]) async {
    final parser = parserFor(sourceId);
    if (!parser.source.isAvailable || !parser.source.isMaintained) {
      return HomePayload(
        sourceId: parser.source.id,
        sections: const [],
        categories: parser.categories,
        notice: parser.source.message,
      );
    }
    final body = await _fetch(parser.homeUrl(_settings), parser);
    final document = html_parser.parse(body);
    final sections = parser.parseHome(document, _settings);
    return HomePayload(
      sourceId: parser.source.id,
      sections: sections,
      categories: parser.categories,
      notice: parser.source.message,
    );
  }

  Future<List<MediaItem>> search(
    String sourceId,
    String query,
    int page, {
    String? verificationCode,
  }) async {
    final parser = parserFor(sourceId);
    if (!parser.source.canSearch) {
      throw AppError('当前站点不支持搜索');
    }
    if (!parser.source.isAvailable || !parser.source.isMaintained) {
      throw AppError(
          parser.source.message.isEmpty ? '当前站点不可用' : parser.source.message);
    }
    final code = verificationCode?.trim() ?? '';
    final rawSearchUrl = parser.searchUrl(_settings, query, page);
    var url = rawSearchUrl;
    String body;
    if (code.isEmpty) {
      body = await _fetch(url, parser, useCache: false);
    } else {
      final verifiedBody = await parser.loadVerifiedSearchBody(
        clientFor(parser),
        _settings,
        query,
        page,
        code,
      );
      if (verifiedBody != null) {
        body = verifiedBody;
      } else {
        url = parser.verifiedSearchUrl(_settings, query, page, code);
        body = await _fetch(url, parser, useCache: false);
      }
    }
    final document = html_parser.parse(body);
    final captchaUrl = parser.searchCaptchaImageUrl(document, _settings, url);
    if (captchaUrl != null) {
      final imageBytes = await clientFor(parser).getBytes(
        captchaUrl,
        headers: {
          ...parser.requestHeaders(_settings),
          'Referer': url,
        },
      );
      throw SearchCaptchaRequired(
        imageUrl: captchaUrl,
        imageBytes: imageBytes,
        message: code.isEmpty ? '请输入验证码后继续搜索' : '验证码不正确，请重新输入',
      );
    }
    return parser.parseList(document, _settings);
  }

  Future<List<MediaItem>> browse(String sourceId, String path, int page) async {
    final parser = parserFor(sourceId);
    if (!parser.source.isAvailable || !parser.source.isMaintained) {
      throw AppError(
          parser.source.message.isEmpty ? '当前站点不可用' : parser.source.message);
    }
    final body =
        await _fetch(parser.categoryUrl(_settings, path, page), parser);
    return parser.parseList(html_parser.parse(body), _settings);
  }

  Future<MediaDetail> detail(String sourceId, String url) async {
    final parser = parserFor(sourceId);
    if (!parser.source.isAvailable || !parser.source.isMaintained) {
      throw AppError(
          parser.source.message.isEmpty ? '当前站点不可用' : parser.source.message);
    }
    final resolved = parser.detailPageUrl(_settings, url);
    final body = await _fetch(resolved, parser);
    return parser.parseDetail(html_parser.parse(body), _settings, resolved);
  }

  Future<List<PlayItem>> playItems(String sourceId, String episodeUrl) async {
    final parser = parserFor(sourceId);
    final items =
        await parser.loadPlayItems(clientFor(parser), _settings, episodeUrl);
    if (items.isEmpty) {
      throw AppError('未找到可直接播放的公开视频地址');
    }
    return items;
  }

  // --- Favorites cache ---
  Set<String>? _favoriteIdCache;
  List<FavoriteEntry>? _favoriteListCache;

  Future<List<FavoriteEntry>> favorites() async {
    if (_favoriteListCache != null) return _favoriteListCache!;
    final list = await store.readFavorites();
    _favoriteListCache = list.map(FavoriteEntry.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _favoriteListCache!;
  }

  Future<bool> isFavorite(String sourceId, String detailUrl) async {
    final id = _entryId(sourceId, detailUrl);
    if (_favoriteIdCache != null) return _favoriteIdCache!.contains(id);
    final list = await favorites();
    _favoriteIdCache = list.map((item) => item.id).toSet();
    return _favoriteIdCache!.contains(id);
  }

  Future<void> toggleFavorite(MediaDetail detail, String sourceId) async {
    final id = _entryId(sourceId, detail.url);
    final list = await favorites();
    final existing = list.indexWhere((item) => item.id == id);
    if (existing >= 0) {
      list.removeAt(existing);
    } else {
      list.add(
        FavoriteEntry(
          id: id,
          sourceId: sourceId,
          title: detail.title,
          detailUrl: detail.url,
          poster: detail.poster,
          summary: detail.summary,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    await store.writeFavorites(list.map((item) => item.toJson()).toList());
    _favoriteListCache = null;
    _favoriteIdCache = null;
  }

  // --- History cache ---
  List<HistoryEntry>? _historyCache;

  Future<List<HistoryEntry>> history() async {
    if (_historyCache != null) return _historyCache!;
    final list = await store.readHistory();
    _historyCache = list.map(HistoryEntry.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _historyCache!;
  }

  Future<void> saveHistory(HistoryEntry entry) async {
    final list = await history();
    list.removeWhere((item) => item.id == entry.id);
    list.add(entry);
    await store
        .writeHistory(list.take(300).map((item) => item.toJson()).toList());
    _historyCache = null;
  }

  Future<void> clearCache() => store.clearCache();

  Future<String> _fetch(
    String url,
    SiteParser parser, {
    Duration maxAge = const Duration(hours: 1),
    bool useCache = true,
  }) async {
    if (url.isEmpty) throw AppError('访问地址为空');
    final key = base64Url.encode(utf8.encode(url));
    if (useCache && _settings.cacheEnabled) {
      final cached = await store.readCache(key, maxAge);
      if (cached != null) return cached;
    }
    final body = await clientFor(parser)
        .getText(url, headers: parser.requestHeaders(_settings));
    if (useCache && _settings.cacheEnabled && body.isNotEmpty) {
      await store.writeCache(key, body);
    }
    return body;
  }
}

String _entryId(String sourceId, String url) {
  return base64Url.encode(utf8.encode('$sourceId::$url'));
}

final homeProvider = FutureProvider.autoDispose<HomePayload>((ref) {
  final sourceId = ref.watch(
    settingsControllerProvider.select((s) => s.sourceId),
  );
  return ref.read(contentRepositoryProvider).home(sourceId);
});
