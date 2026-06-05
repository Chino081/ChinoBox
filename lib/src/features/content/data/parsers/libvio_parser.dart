import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../../core/network/movies_http_client.dart';
import '../../../settings/app_settings.dart';
import '../../../source/domain/source_catalog.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
import '../site_parser.dart';
import 'generic_maccms_parser.dart';

class LibvioParser extends GenericMaccmsParser {
  LibvioParser()
      : super(
          sourceById('libvio'),
          searchTemplate: '/search/%s----------%p---.html',
          categoryTemplate: '/show/%s--------%p---.html',
        );

  @override
  Map<String, String> requestHeaders(AppSettings settings) => {
        'Referer': '${domain(settings)}/',
      };

  @override
  Map<String, String> playerHeaders(AppSettings settings) => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
        'Referer': '${domain(settings)}/',
      };

  @override
  Future<List<PlayItem>> loadPlayItems(
    MoviesHttpClient client,
    AppSettings settings,
    String episodeUrl,
  ) async {
    final resolved = episodePageUrl(settings, episodeUrl);
    final body =
        await client.getText(resolved, headers: requestHeaders(settings));
    final direct = parsePlayItems(html_parser.parse(body), settings);
    if (direct.isNotEmpty) return direct;

    final playerData = _playerDataFromHtml(body);
    if (playerData == null) return const [];
    final iframe = await _loadIframePlayItems(
      client,
      settings,
      playerData,
      referer: resolved,
    );
    if (iframe.isNotEmpty) return iframe;

    return const [];
  }

  Future<List<PlayItem>> _loadIframePlayItems(
    MoviesHttpClient client,
    AppSettings settings,
    _LibvioPlayerData playerData, {
    required String referer,
  }) async {
    final knownPaths = _knownIframePaths(playerData.from);
    final firstPaths = knownPaths.isNotEmpty
        ? [
            ...knownPaths,
            if (playerData.from.isNotEmpty) '/vid/${playerData.from}.php',
          ]
        : await _scriptIframePaths(client, settings, playerData.from);
    final first = await _loadIframeUrls(
      client,
      settings,
      playerData,
      firstPaths,
      referer: referer,
    );
    if (first.isNotEmpty) return first;

    final fallbackPaths = knownPaths.isNotEmpty
        ? await _scriptIframePaths(client, settings, playerData.from)
        : [
            if (playerData.from.isNotEmpty) '/vid/${playerData.from}.php',
          ];
    return _loadIframeUrls(
      client,
      settings,
      playerData,
      fallbackPaths,
      referer: referer,
    );
  }

  Future<List<PlayItem>> _loadIframeUrls(
    MoviesHttpClient client,
    AppSettings settings,
    _LibvioPlayerData playerData,
    List<String> paths, {
    required String referer,
  }) async {
    final iframeUrls = _iframeUrlsFromPaths(paths, settings, playerData);

    for (final iframeUrl in iframeUrls) {
      String iframeBody;
      try {
        iframeBody = await client.getText(
          iframeUrl,
          headers: {
            ...requestHeaders(settings),
            'Referer': referer,
          },
        );
      } catch (_) {
        continue;
      }

      final normalizedBody = iframeBody.replaceAll(r'\/', '/');
      try {
        final parseItems =
            await _loadParseResponsePlayItems(client, settings, normalizedBody);
        if (parseItems.isNotEmpty) return parseItems;
      } catch (_) {}

      final direct = extractDirectPlayItems(
        normalizedBody,
        headers: playerHeaders(settings),
      );
      if (direct.isNotEmpty) return direct;
    }
    return const [];
  }

  Future<List<PlayItem>> _loadParseResponsePlayItems(
    MoviesHttpClient client,
    AppSettings settings,
    String iframeBody,
  ) async {
    final parsePath = _parsePathFromIframe(iframeBody);
    if (parsePath == null || parsePath.isEmpty) return const [];

    final parseUrl = absolutize(parsePath, domain(settings));
    final jsonBody = await client.getText(parseUrl, headers: const {
      'Accept': '*/*',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
    });
    return _playItemsFromParseResponse(jsonBody);
  }

  String? _parsePathFromIframe(String iframeBody) {
    final paths = RegExp(
      r'''['"]([^'"]*parse_[^'"]+?\.php[^'"]*)['"]''',
      caseSensitive: false,
    )
        .allMatches(iframeBody)
        .map((match) => match.group(1) ?? '')
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.isEmpty) return null;

    bool looksComplete(String path) {
      final lower = path.toLowerCase();
      return lower.contains('token=') ||
          lower.contains('_t=') ||
          lower.contains('exp=') ||
          lower.contains('sig=') ||
          lower.contains('url=');
    }

    for (final path in paths) {
      if (looksComplete(path)) return path;
    }
    return paths.last;
  }

  List<String> _iframeUrlsFromPaths(
    List<String> paths,
    AppSettings settings,
    _LibvioPlayerData playerData,
  ) {
    final urls = <String>[];
    final seen = <String>{};
    for (final path in paths) {
      final url = _iframeUrl(path, settings, playerData);
      if (url.isNotEmpty && seen.add(url)) urls.add(url);
    }
    return urls;
  }

  List<String> _knownIframePaths(String from) {
    return switch (from) {
      'yd189' => const ['/vid/yd.php'],
      'vr2' => const ['/vid/plyr/vr2.php'],
      'qq' => const ['/vid/qq.php'],
      'ffm3u8' => const ['/vid/ffm3u8.php'],
      _ => const [],
    };
  }

  Future<List<String>> _scriptIframePaths(
    MoviesHttpClient client,
    AppSettings settings,
    String from,
  ) async {
    if (from.isEmpty) return const [];
    final scriptUrl =
        absolutize('/static/player/$from.js?v=3.9', domain(settings));
    String body;
    try {
      body = await client.getText(
        scriptUrl,
        headers: requestHeaders(settings),
      );
    } catch (_) {
      return const [];
    }
    return RegExp(
      r'''src=["']([^"']+?\.php)\?''',
      caseSensitive: false,
    )
        .allMatches(body)
        .map((match) => match.group(1) ?? '')
        .where((path) => path.isNotEmpty)
        .toList();
  }

  String _iframeUrl(
    String path,
    AppSettings settings,
    _LibvioPlayerData playerData,
  ) {
    if (path.isEmpty) return '';
    return Uri.parse(absolutize(path, domain(settings))).replace(
      queryParameters: {
        'url': playerData.url,
        if (playerData.linkNext.isNotEmpty) 'next': playerData.linkNext,
        if (playerData.id.isNotEmpty) 'id': playerData.id,
        if (playerData.nid.isNotEmpty) 'nid': playerData.nid,
      },
    ).toString();
  }

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    final base = domain(settings);
    final root =
        document.body ?? document.documentElement ?? Element.tag('html');
    final hero = root.querySelector('.vod-hero__inner') ?? root;
    final resolved = absolutize(url, base);
    final groups = _parseEpisodeGroups(root, base);

    return MediaDetail(
      title: firstNonEmpty([
        textOf(hero, '.vod-info h1'),
        textOf(root, 'h1'),
      ]),
      url: resolved,
      poster: imageFromElement(root.querySelector('.vod-poster') ?? hero, base),
      summary: firstNonEmpty([
        textOf(hero, 'span.detail-content'),
        textOf(hero, '.detail-content'),
      ]),
      score: textOf(hero, '.vod-rating .score'),
      updateText: firstNonEmpty([
        for (final item in hero.querySelectorAll('.meta-item'))
          cleanText(item.text).contains('更新') ? cleanText(item.text) : '',
      ]),
      metadata: hero
          .querySelectorAll('.meta-item')
          .map((item) => cleanText(item.text))
          .where((text) => text.isNotEmpty)
          .take(8)
          .toList(),
      groups: groups,
      recommendations: _parseVodCards(root, base)
          .where((item) => item.url != resolved)
          .take(12)
          .toList(),
    );
  }

  @override
  List<Episode> parseCurrentEpisodes(
    Document document,
    AppSettings settings,
    int groupIndex,
    String currentUrl,
  ) {
    final groups = _parsePlayPageEpisodeGroups(
      document.body ?? document.documentElement ?? Element.tag('html'),
      domain(settings),
    );
    if (groupIndex >= 0 && groupIndex < groups.length) {
      return groups[groupIndex].episodes;
    }
    return groups.expand((group) => group.episodes).toList();
  }

  List<EpisodeGroup> _parseEpisodeGroups(Element root, String base) {
    final groups = <EpisodeGroup>[];
    for (final panel in root.querySelectorAll('.playlist-panel')) {
      if (panel.classes.contains('netdisk-panel')) continue;
      final title =
          cleanText(panel.querySelector('.panel-head h3')?.text ?? '');
      if (title.contains('下载')) continue;
      final episodes = _parseEpisodeAnchors(panel, base);
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(
          title: title.isEmpty ? '播放源 ${groups.length + 1}' : title,
          episodes: episodes,
        ));
      }
    }

    if (groups.isEmpty && !_hasNetdiskOnlyPanels(root)) {
      final playButton = root.querySelector('.play-btn a[href*="/w/"]');
      if (playButton != null) {
        final href = playButton.attributes['href'] ?? '';
        final title = cleanText(playButton.text);
        groups.add(EpisodeGroup(
          title: '播放列表',
          episodes: [
            Episode(
              title: title.isEmpty ? '立即播放' : title,
              url: absolutize(href, base),
            ),
          ],
        ));
      }
    }
    return groups;
  }

  bool _hasNetdiskOnlyPanels(Element root) {
    return root
            .querySelector('.playlist-panel.netdisk-panel, .netdisk-panel') !=
        null;
  }

  List<EpisodeGroup> _parsePlayPageEpisodeGroups(Element root, String base) {
    final titles = root.querySelectorAll('.play-tab li a');
    final lists = root.querySelectorAll('.play-content .stui-play__list');
    final groups = <EpisodeGroup>[];
    for (var i = 0; i < lists.length; i++) {
      final title = i < titles.length ? cleanText(titles[i].text) : '';
      if (title.contains('下载')) continue;
      final episodes = _parseEpisodeAnchors(lists[i], base);
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(
          title: title.isEmpty ? '播放源 ${groups.length + 1}' : title,
          episodes: episodes,
        ));
      }
    }
    return groups;
  }

  List<Episode> _parseEpisodeAnchors(Element root, String base) {
    final episodes = <Episode>[];
    final seen = <String>{};
    for (final anchor in root.querySelectorAll('a[href*="/w/"]')) {
      final href = anchor.attributes['href'] ?? '';
      final title = cleanText(anchor.text);
      if (href.isEmpty || title.isEmpty) continue;
      final url = absolutize(href, base);
      if (seen.add(url)) episodes.add(Episode(title: title, url: url));
    }
    return episodes;
  }

  List<MediaItem> _parseVodCards(Element root, String base) {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final anchor in root.querySelectorAll('a.stui-vodlist__thumb')) {
      final href = anchor.attributes['href'] ?? '';
      final title = anchor.attributes['title'] ?? '';
      if (href.isEmpty || title.isEmpty) continue;
      final url = absolutize(href, base);
      if (!seen.add(url)) continue;
      items.add(MediaItem(
        title: title,
        url: url,
        poster: imageFromElement(anchor, base),
        subtitle: firstNonEmpty([
          textOf(anchor, '.pic-text'),
          textOf(anchor, '.text-right'),
        ]),
        sourceId: source.id,
      ));
    }
    return items;
  }

  _LibvioPlayerData? _playerDataFromHtml(String html) {
    final playerJson =
        RegExp(r'player_aaaa\s*=\s*(\{.*?\})\s*;?\s*<', dotAll: true)
            .firstMatch('$html<')
            ?.group(1);
    if (playerJson == null || playerJson.isEmpty) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(playerJson);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final encrypt = int.tryParse(decoded['encrypt']?.toString() ?? '') ?? 0;
    final rawUrl = decoded['url']?.toString() ?? '';
    final rawNext = decoded['link_next']?.toString() ?? '';
    final url = _decodeMacPlayerValue(rawUrl, encrypt);
    final linkNext = rawNext.replaceAll(r'\/', '/');
    if (url.isEmpty) return null;

    return _LibvioPlayerData(
      from: decoded['from']?.toString() ?? '',
      url: url,
      linkNext: linkNext,
      id: decoded['id']?.toString() ?? '',
      nid: decoded['nid']?.toString() ?? '',
    );
  }

  List<PlayItem> _playItemsFromParseResponse(String jsonBody) {
    final urls = <String>{};
    Object? decoded;
    try {
      decoded = jsonDecode(jsonBody);
    } catch (_) {
      decoded = null;
    }

    void addValue(Object? value) {
      if (value == null) return;
      if (value is Map) {
        for (final item in value.values) {
          addValue(item);
        }
        return;
      }
      if (value is Iterable) {
        for (final item in value) {
          addValue(item);
        }
        return;
      }
      final text = value.toString().replaceAll(r'\/', '/');
      for (final part in text.split(',')) {
        final url = _cleanParseUrl(part);
        if (_looksPlayableUrl(url)) urls.add(url);
      }
    }

    if (decoded is Map<String, dynamic>) {
      for (final key in const ['url', 'data', 'm3u8', 'playurl']) {
        addValue(decoded[key]);
      }
    } else {
      for (final item in extractDirectPlayItems(
        jsonBody.replaceAll(r'\/', '/'),
      )) {
        addValue(item.url);
      }
    }

    return urls
        .map((url) => PlayItem(
              url: url,
              type: playTypeFor(url),
            ))
        .toList();
  }

  String _cleanParseUrl(String value) {
    var cleaned = value.trim();
    if (!cleaned.startsWith('http') && cleaned.contains(r'$')) {
      cleaned = cleaned.substring(cleaned.lastIndexOf(r'$') + 1);
    }
    return cleaned.split('#').first.trim();
  }

  bool _looksPlayableUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http') &&
        (lower.contains('.m3u8') || lower.contains('.mp4'));
  }

  String _decodeMacPlayerValue(String value, int encrypt) {
    if (value.isEmpty) return '';
    final normalized = value.replaceAll(r'\/', '/');
    try {
      return switch (encrypt) {
        1 => Uri.decodeFull(normalized),
        2 => Uri.decodeFull(utf8.decode(base64Decode(normalized))),
        _ => normalized,
      };
    } catch (_) {
      return normalized;
    }
  }
}

class _LibvioPlayerData {
  const _LibvioPlayerData({
    required this.from,
    required this.url,
    required this.linkNext,
    required this.id,
    required this.nid,
  });

  final String from;
  final String url;
  final String linkNext;
  final String id;
  final String nid;
}
