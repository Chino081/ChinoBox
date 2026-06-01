import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../settings/app_settings.dart';
import '../../source/domain/media_source.dart';
import '../domain/content_models.dart';
import '../../../core/network/movies_http_client.dart';
import 'html_helpers.dart';

abstract class SiteParser {
  SiteParser(this.source);

  final MediaSource source;

  String domain(AppSettings settings) {
    final userDomain = settings.userDomains[source.id]?.trim() ?? '';
    return userDomain.isNotEmpty ? userDomain : source.defaultDomain;
  }

  int get startPage => 1;
  String get charset => 'UTF-8';
  Map<String, String> requestHeaders(AppSettings settings) => const {};
  Map<String, String> imageHeaders(AppSettings settings) =>
      requestHeaders(settings);
  Map<String, String> playerHeaders(AppSettings settings) => const {};
  List<CategoryGroup> get categories => const [];

  bool get supportsDirectPlay => true;

  String homeUrl(AppSettings settings) => domain(settings);

  String searchUrl(AppSettings settings, String query, int page);

  String categoryUrl(AppSettings settings, String path, int page);

  String detailPageUrl(AppSettings settings, String url) {
    return absolutize(url, domain(settings));
  }

  String episodePageUrl(AppSettings settings, String url) {
    return absolutize(url, domain(settings));
  }

  List<HomeSection> parseHome(Document document, AppSettings settings);

  List<MediaItem> parseList(Document document, AppSettings settings);

  MediaDetail parseDetail(Document document, AppSettings settings, String url);

  List<Episode> parseCurrentEpisodes(
    Document document,
    AppSettings settings,
    int groupIndex,
    String currentUrl,
  ) {
    return const [];
  }

  List<PlayItem> parsePlayItems(Document document, AppSettings settings) {
    final html =
        document.documentElement?.outerHtml ?? document.body?.outerHtml ?? '';
    return extractDirectPlayItems(html, headers: playerHeaders(settings));
  }

  Future<List<PlayItem>> loadPlayItems(
    MoviesHttpClient client,
    AppSettings settings,
    String episodeUrl,
  ) async {
    final resolved = episodePageUrl(settings, episodeUrl);
    final body =
        await client.getText(resolved, headers: requestHeaders(settings));
    return parsePlayItems(html_parser.parse(body), settings);
  }
}

class UnavailableParser extends SiteParser {
  UnavailableParser(super.source);

  @override
  String searchUrl(AppSettings settings, String query, int page) => '';

  @override
  String categoryUrl(AppSettings settings, String path, int page) => '';

  @override
  List<HomeSection> parseHome(Document document, AppSettings settings) =>
      const [];

  @override
  List<MediaItem> parseList(Document document, AppSettings settings) =>
      const [];

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    return MediaDetail(title: source.name, url: url, summary: source.message);
  }
}

List<PlayItem> extractDirectPlayItems(
  String html, {
  Map<String, String> headers = const {},
}) {
  final urls = <String>{};
  final playerJson =
      RegExp(r'player_aaaa\s*=\s*(\{.*?\})\s*;?\s*<', dotAll: true)
          .firstMatch('$html<')
          ?.group(1);
  if (playerJson != null) {
    final url = _decodePlayerUrl(playerJson);
    if (url != null && _looksPlayable(url)) {
      urls.add(url);
    }
  }

  for (final match in RegExp(
    r'https?://[^\s"<>]+?\.(?:m3u8|mp4)(?:\?[^\s"<>]*)?',
    caseSensitive: false,
  ).allMatches(html)) {
    urls.add(match.group(0)!);
  }

  return urls.map((url) {
    final lower = url.toLowerCase();
    final type = lower.contains('.m3u8')
        ? PlayType.m3u8
        : lower.contains('.mp4')
            ? PlayType.mp4
            : PlayType.other;
    return PlayItem(url: url, type: type, headers: headers);
  }).toList();
}

bool _looksPlayable(String url) {
  final value = url.toLowerCase();
  if (!value.startsWith('http')) return false;
  return value.contains('.m3u8') || value.contains('.mp4');
}

String? _decodePlayerUrl(String playerJson) {
  Object? decoded;
  try {
    decoded = jsonDecode(playerJson);
  } catch (_) {
    decoded = null;
  }

  String? rawUrl;
  int encrypt = 0;
  if (decoded is Map<String, dynamic>) {
    rawUrl = decoded['url']?.toString();
    encrypt = int.tryParse(decoded['encrypt']?.toString() ?? '') ?? 0;
  } else {
    rawUrl = RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(playerJson)?.group(1);
    encrypt = int.tryParse(
          RegExp(r'"encrypt"\s*:\s*(\d+)').firstMatch(playerJson)?.group(1) ??
              '',
        ) ??
        0;
  }

  if (rawUrl == null || rawUrl.isEmpty) return null;
  final normalized = rawUrl.replaceAll(r'\/', '/');
  try {
    return switch (encrypt) {
      1 => _safeUrlDecode(normalized),
      2 => _safeUrlDecode(utf8.decode(base64Decode(normalized))),
      _ => normalized,
    };
  } catch (_) {
    return normalized;
  }
}

String _safeUrlDecode(String value) {
  try {
    return Uri.decodeFull(value);
  } catch (_) {
    final escaped =
        value.replaceAllMapped(RegExp(r'%(?![0-9a-fA-F]{2})'), (_) => '%25');
    return Uri.decodeFull(escaped);
  }
}
