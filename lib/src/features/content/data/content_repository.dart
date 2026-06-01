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
  final settings = ref.watch(settingsControllerProvider);
  return ContentRepository(
    settings: settings,
    store: LocalStore.instance,
    client: MoviesHttpClient(settings),
  );
});

class ContentRepository {
  ContentRepository({
    required this.settings,
    required this.store,
    required this.client,
  });

  final AppSettings settings;
  final LocalStore store;
  final MoviesHttpClient client;

  SiteParser parserFor([String? sourceId]) {
    return ParserRegistry.byId(sourceId ?? settings.sourceId);
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
    final body = await _fetch(parser.homeUrl(settings), parser);
    final document = html_parser.parse(body);
    final sections = parser.parseHome(document, settings);
    return HomePayload(
      sourceId: parser.source.id,
      sections: sections,
      categories: parser.categories,
      notice: parser.source.message,
    );
  }

  Future<List<MediaItem>> search(
      String sourceId, String query, int page) async {
    final parser = parserFor(sourceId);
    if (!parser.source.canSearch) {
      throw AppError('当前站点不支持搜索');
    }
    if (!parser.source.isAvailable || !parser.source.isMaintained) {
      throw AppError(
          parser.source.message.isEmpty ? '当前站点不可用' : parser.source.message);
    }
    final body = await _fetch(parser.searchUrl(settings, query, page), parser);
    return parser.parseList(html_parser.parse(body), settings);
  }

  Future<List<MediaItem>> browse(String sourceId, String path, int page) async {
    final parser = parserFor(sourceId);
    if (!parser.source.isAvailable || !parser.source.isMaintained) {
      throw AppError(
          parser.source.message.isEmpty ? '当前站点不可用' : parser.source.message);
    }
    final body = await _fetch(parser.categoryUrl(settings, path, page), parser);
    return parser.parseList(html_parser.parse(body), settings);
  }

  Future<MediaDetail> detail(String sourceId, String url) async {
    final parser = parserFor(sourceId);
    if (!parser.source.isAvailable || !parser.source.isMaintained) {
      throw AppError(
          parser.source.message.isEmpty ? '当前站点不可用' : parser.source.message);
    }
    final resolved = parser.detailPageUrl(settings, url);
    final body = await _fetch(resolved, parser);
    return parser.parseDetail(html_parser.parse(body), settings, resolved);
  }

  Future<List<PlayItem>> playItems(String sourceId, String episodeUrl) async {
    final parser = parserFor(sourceId);
    final items = await parser.loadPlayItems(client, settings, episodeUrl);
    if (items.isEmpty) {
      throw AppError('未找到可直接播放的公开视频地址');
    }
    return items;
  }

  Future<List<FavoriteEntry>> favorites() async {
    final list = await store.readFavorites();
    return list.map(FavoriteEntry.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<bool> isFavorite(String sourceId, String detailUrl) async {
    final id = _entryId(sourceId, detailUrl);
    final list = await favorites();
    return list.any((item) => item.id == id);
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
  }

  Future<List<HistoryEntry>> history() async {
    final list = await store.readHistory();
    return list.map(HistoryEntry.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveHistory(HistoryEntry entry) async {
    final list = await history();
    list.removeWhere((item) => item.id == entry.id);
    list.add(entry);
    await store
        .writeHistory(list.take(300).map((item) => item.toJson()).toList());
  }

  Future<void> clearCache() => store.clearCache();

  Future<String> _fetch(
    String url,
    SiteParser parser, {
    Duration maxAge = const Duration(hours: 1),
  }) async {
    if (url.isEmpty) throw AppError('访问地址为空');
    final key = base64Url.encode(utf8.encode(url));
    if (settings.cacheEnabled) {
      final cached = await store.readCache(key, maxAge);
      if (cached != null) return cached;
    }
    final body =
        await client.getText(url, headers: parser.requestHeaders(settings));
    if (settings.cacheEnabled && body.isNotEmpty) {
      await store.writeCache(key, body);
    }
    return body;
  }
}

String _entryId(String sourceId, String url) {
  return base64Url.encode(utf8.encode('$sourceId::$url'));
}

final homeProvider = FutureProvider.autoDispose<HomePayload>((ref) async {
  return ref.watch(contentRepositoryProvider).home();
});
