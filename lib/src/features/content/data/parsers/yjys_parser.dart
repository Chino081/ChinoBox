import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';

import '../../../../core/network/movies_http_client.dart';
import '../../../settings/app_settings.dart';
import '../../../source/domain/source_catalog.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
import '../site_parser.dart';

class YjysParser extends SiteParser {
  YjysParser() : super(sourceById('yjys'));

  @override
  List<CategoryGroup> get categories => const [
        CategoryGroup(
          title: '频道',
          options: [
            CategoryOption(title: '全部', path: '/s/all'),
            CategoryOption(title: '电影', path: '/s/all?type=0'),
            CategoryOption(title: '剧集', path: '/s/all?type=1'),
            CategoryOption(title: '动漫', path: '/s/donghua'),
            CategoryOption(title: '综艺', path: '/s/zongyi'),
          ],
        ),
        CategoryGroup(
          title: '电影类型',
          options: [
            CategoryOption(title: '动作', path: '/s/dongzuo'),
            CategoryOption(title: '爱情', path: '/s/aiqing'),
            CategoryOption(title: '喜剧', path: '/s/xiju'),
            CategoryOption(title: '科幻', path: '/s/kehuan'),
            CategoryOption(title: '恐怖', path: '/s/kongbu'),
            CategoryOption(title: '战争', path: '/s/zhanzheng'),
            CategoryOption(title: '剧情', path: '/s/juqing'),
            CategoryOption(title: '动画', path: '/s/donghua'),
            CategoryOption(title: '悬疑', path: '/s/xuanyi'),
            CategoryOption(title: '犯罪', path: '/s/fanzui'),
            CategoryOption(title: '纪录', path: '/s/jilu'),
          ],
        ),
        CategoryGroup(
          title: '剧集地区',
          options: [
            CategoryOption(title: '国产剧', path: '/s/guoju'),
            CategoryOption(title: '美剧', path: '/s/meiju'),
            CategoryOption(title: '韩剧', path: '/s/hanju'),
            CategoryOption(title: '日剧', path: '/s/riju'),
            CategoryOption(title: '英剧', path: '/s/yingju'),
            CategoryOption(title: '港台剧', path: '/s/gangtaiju'),
            CategoryOption(title: '泰剧', path: '/s/taiju'),
            CategoryOption(title: '短剧', path: '/s/duanju'),
          ],
        ),
      ];

  @override
  String searchUrl(AppSettings settings, String query, int page) {
    return '${domain(settings)}/search/${Uri.encodeComponent(query)}/$page';
  }

  @override
  String verifiedSearchUrl(
    AppSettings settings,
    String query,
    int page,
    String code,
  ) {
    final uri = Uri.parse(searchUrl(settings, query, page));
    return uri.replace(queryParameters: {'code': code}).toString();
  }

  @override
  String categoryUrl(AppSettings settings, String path, int page) {
    final uri = Uri.parse(path);
    if (page <= 1) {
      return absolutize(uri.toString(), domain(settings));
    }
    final trimmedPath = uri.path.replaceFirst(RegExp(r'/$'), '');
    final paged = uri.replace(path: '$trimmedPath/$page');
    return absolutize(paged.toString(), domain(settings));
  }

  @override
  String? searchCaptchaImageUrl(
    Document document,
    AppSettings settings,
    String responseUrl,
  ) {
    final root = document.body ?? document.documentElement;
    if (root == null || root.querySelector('#code') == null) return null;
    final src = root.querySelector('#verifyCode')?.attributes['src'] ?? '';
    if (src.isEmpty) return null;
    return absolutize(src, domain(settings));
  }

  @override
  List<HomeSection> parseHome(Document document, AppSettings settings) {
    final base = domain(settings);
    final banners = document
        .querySelectorAll('.banner-slide')
        .map((e) {
          return MediaItem(
            title: textOf(e, 'h1'),
            url: absolutize(attrOf(e, 'a', 'href'), base),
            poster: absolutize(attrOf(e, 'img', 'src'), base),
            subtitle: textOf(e, 'p.banner-desc'),
            sourceId: source.id,
          );
        })
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();
    final cards = parseList(document, settings);
    return [
      if (banners.isNotEmpty) HomeSection(title: '推荐', items: banners),
      if (cards.isNotEmpty)
        HomeSection(title: '影视列表', items: cards.take(36).toList()),
    ];
  }

  @override
  List<MediaItem> parseList(Document document, AppSettings settings) {
    final base = domain(settings);
    return document
        .querySelectorAll('.movie-card, .xl-result-item')
        .map((e) {
          return MediaItem(
            title:
                firstNonEmpty([textOf(e, 'h4'), textOf(e, 'a.xl-result-name')]),
            url: absolutize(
                firstAttr(e, ['a', 'a.xl-result-name'], 'href'), base),
            poster: imageFromElement(e, base),
            subtitle: firstNonEmpty(
                [textOf(e, '.rating-badge'), textOf(e, '.episode-badge')]),
            sourceId: source.id,
          );
        })
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();
  }

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    final base = domain(settings);
    final root = document.body ?? document.documentElement!;
    final groups = _parseEpisodeGroups(root, base);

    final tags = root
        .querySelectorAll('.info-list .info-item a.info-value')
        .map((a) {
          return DetailTag(
              cleanText(a.text), absolutize(a.attributes['href'] ?? '', base));
        })
        .where((tag) => tag.title.isNotEmpty)
        .toList();

    return MediaDetail(
      title: textOf(root, 'h1.movie-title'),
      url: absolutize(url, base),
      poster: absolutize(attrOf(root, '.movie-poster img', 'src'), base),
      summary: textOf(root, '.desc'),
      score: textOf(root, '.score-text'),
      tags: tags,
      groups: groups,
      recommendations: parseList(document, settings).take(12).toList(),
    );
  }

  @override
  List<Episode> parseCurrentEpisodes(
    Document document,
    AppSettings settings,
    int groupIndex,
    String currentUrl,
  ) {
    final groups = _parseEpisodeGroups(
      document.body ?? document.documentElement ?? Element.tag('html'),
      domain(settings),
    );
    if (groupIndex >= 0 && groupIndex < groups.length) {
      return groups[groupIndex].episodes;
    }
    return groups.expand((group) => group.episodes).toList();
  }

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

    final pid = RegExp(r'var\s+pid\s*=\s*(\d+)').firstMatch(body)?.group(1);
    if (pid == null || pid.isEmpty) return const [];
    return _loadLinePlayItems(client, settings, pid, referer: resolved);
  }

  List<EpisodeGroup> _parseEpisodeGroups(Element root, String base) {
    final groups = <EpisodeGroup>[];
    for (final list in root.querySelectorAll('.play-list, .btn-group')) {
      final episodes = _parseEpisodeAnchors(list, base);
      if (episodes.isEmpty) continue;
      groups.add(EpisodeGroup(
        title: groups.isEmpty ? '在线播放' : '播放源 ${groups.length + 1}',
        episodes: episodes,
      ));
    }
    return groups;
  }

  List<Episode> _parseEpisodeAnchors(Element root, String base) {
    final episodes = <Episode>[];
    final seen = <String>{};
    for (final anchor in root.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      final title = cleanText(anchor.text);
      if (href.isEmpty || title.isEmpty || !href.contains('/play/')) continue;
      final url = absolutize(href, base);
      if (seen.add(url)) episodes.add(Episode(title: title, url: url));
    }
    return episodes;
  }

  Future<List<PlayItem>> _loadLinePlayItems(
    MoviesHttpClient client,
    AppSettings settings,
    String pid, {
    required String referer,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final signature = _lineSignature(pid, timestamp);
    final api = Uri.parse(domain(settings)).replace(
      path: '/lines',
      queryParameters: {
        't': timestamp,
        'sg': signature,
        'pid': pid,
      },
    ).toString();
    final body = await client.getText(
      api,
      headers: {
        ...requestHeaders(settings),
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': referer,
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
    return _parseLinePlayItems(body, domain(settings));
  }

  List<PlayItem> _parseLinePlayItems(String body, String base) {
    final items = <PlayItem>[];
    final seen = <String>{};
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return const [];

    void addUrl(String value) {
      final cleaned = _cleanPlayUrl(value, base);
      if (cleaned.isEmpty || !cleaned.startsWith('http')) return;
      if (seen.add(cleaned)) {
        items.add(PlayItem(url: cleaned, type: _playType(cleaned)));
      }
    }

    for (final key in const ['url3', 'm3u8', 'm3u8_2']) {
      final value = data[key]?.toString() ?? '';
      for (final part in value.split(',')) {
        addUrl(part);
      }
    }
    return items;
  }

  String _lineSignature(String pid, String timestamp) {
    final plain = '$pid-$timestamp';
    final keyText = md5.convert(utf8.encode(plain)).toString().substring(0, 16);
    final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(Uint8List.fromList(utf8.encode(keyText))),
          null,
        ),
      );
    final encrypted = cipher.process(Uint8List.fromList(utf8.encode(plain)));
    return encrypted
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _cleanPlayUrl(String value, String base) {
    final withoutName = value.split('#').first.trim();
    if (withoutName.isEmpty) return '';
    return withoutName.replaceFirst('https://www.bde4.cc', base);
  }

  PlayType _playType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return PlayType.m3u8;
    if (lower.contains('.mp4')) return PlayType.mp4;
    return PlayType.other;
  }
}
