import 'package:html/dom.dart';

import '../../../../core/network/movies_http_client.dart';
import '../../../settings/app_settings.dart';
import '../../../source/domain/source_catalog.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
import '../silisili_crypto.dart';
import '../site_parser.dart';

class SilisiliParser extends SiteParser {
  SilisiliParser() : super(sourceById('silisili'));

  @override
  bool get needsProxy => false;

  static const _defaultAccessCookie = String.fromEnvironment(
    'MOVIESBOX_SILISILI_COOKIE',
    defaultValue: 'silisili=on;path=/;max-age=86400',
  );

  @override
  Map<String, String> requestHeaders(AppSettings settings) {
    final cookie =
        settings.sourceCookies[source.id]?.trim() ?? _defaultAccessCookie;
    return {
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': domain(settings),
      'Referer': domain(settings),
      'Sec-Ch-Ua':
          '"Microsoft Edge";v="117", "Not;A=Brand";v="8", "Chromium";v="117"',
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': '"Windows"',
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  @override
  List<CategoryGroup> get categories => const [
        CategoryGroup(
          title: '频道',
          options: [
            CategoryOption(title: '新番日漫', path: '/vodshow/id/xinfanriman/'),
            CategoryOption(title: '新番国漫', path: '/vodshow/id/xinfanguoman/'),
            CategoryOption(title: '动漫番剧', path: '/vodshow/id/dongmanfanju/'),
            CategoryOption(title: '剧场动漫', path: '/vodshow/id/juchang/'),
            CategoryOption(title: '4K专区', path: '/vodshow/id/4Kzhuanqu/'),
          ],
        ),
      ];

  @override
  String searchUrl(AppSettings settings, String query, int page) {
    return '${domain(settings)}/vodsearch/?wd=${Uri.encodeComponent(query)}&page=$page';
  }

  @override
  String categoryUrl(AppSettings settings, String path, int page) {
    // New format: /vodshow/id/xxx/ → /vodshow/id/xxx/page/N
    // Old format: /vodshow/2--------1---/ → /vodshow/2--------N---/
    final replaced = path.replaceFirst(RegExp(r'page/\d+'), 'page/$page');
    if (replaced == path && page > 1) {
      // New URL format: append page segment
      final normalized = path.endsWith('/') ? path : '$path/';
      return absolutize('${normalized}page/$page', domain(settings));
    }
    return absolutize(replaced, domain(settings));
  }

  @override
  List<HomeSection> parseHome(Document document, AppSettings settings) {
    final base = domain(settings);
    final sections = <HomeSection>[];
    final bannerItems = document
        .querySelectorAll('div.focus div.swiper-slide')
        .map((e) {
          final votitle = e.querySelector('div.swiper-slide-votitle');
          votitle?.querySelectorAll('span.badge').forEach((s) => s.remove());
          return MediaItem(
            title: firstNonEmpty([
              cleanText(votitle?.text ?? ''),
              attrOf(e, 'a', 'title'),
            ]),
            url: absolutize(attrOf(e, 'a', 'href'), base),
            poster: absolutize(_cssImage(attrOf(e, 'a', 'style')), base),
            subtitle: textOf(e, 'div.swiper-slide-vodesc'),
            sourceId: source.id,
          );
        })
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();
    if (bannerItems.isNotEmpty) {
      sections.add(HomeSection(title: '推荐', items: bannerItems, isBanner: true));
    }

    final updateItems = document
        .querySelectorAll('article.article')
        .map((e) {
          final titleNode = e.querySelector('h2.entry-title');
          titleNode?.querySelectorAll('span.badge').forEach((s) => s.remove());
          return MediaItem(
            title: cleanText(titleNode?.text ?? ''),
            url: absolutize(
                titleNode?.querySelector('a')?.attributes['href'] ?? '', base),
            poster:
                absolutize(attrOf(e, 'img.scrollLoading, img', 'src'), base),
            subtitle: textOf(e, 'div.entry-meta'),
            sourceId: source.id,
          );
        })
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();
    if (updateItems.isNotEmpty) {
      sections.add(HomeSection(title: '最近更新', items: updateItems));
    }

    final hotItems = _listItems(document, base).take(24).toList();
    if (hotItems.isNotEmpty) {
      sections.add(HomeSection(title: '动漫列表', items: hotItems));
    }
    return sections;
  }

  @override
  List<MediaItem> parseList(Document document, AppSettings settings) {
    return _listItems(document, domain(settings));
  }

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    final base = domain(settings);
    final root = document.body ?? document.documentElement!;
    final title = cleanText(root
            .querySelector('h1.entry-title')
            ?.nodes
            .whereType<Text>()
            .map((e) => e.text)
            .join(' ') ??
        textOf(root, 'h1.entry-title'));
    final groups = <EpisodeGroup>[];
    for (final panel in root.querySelectorAll('div.play-pannel-box')) {
      final name = firstNonEmpty([
        textOf(panel, 'div.widget-title'),
        '播放源 ${groups.length + 1}',
      ]);
      if (_isHiddenPlaySource(name)) continue;
      final episodes = panel
          .querySelectorAll('ul li a')
          .map((a) {
            return Episode(
                title: cleanText(a.text),
                url: absolutize(a.attributes['href'] ?? '', base));
          })
          .where(
              (episode) => episode.title.isNotEmpty && episode.url.isNotEmpty)
          .toList();
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(title: name, episodes: episodes));
      }
    }
    final recommendations = root
        .querySelectorAll('div.vod_hl_list a')
        .map((a) {
          return MediaItem(
            title: textOf(a, 'div.list-body'),
            url: absolutize(a.attributes['href'] ?? '', base),
            poster: absolutize(_cssImage(attrOf(a, 'i.thumb', 'style')), base),
            sourceId: source.id,
          );
        })
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();

    final tagGroups = <TagGroup>[];
    var updateText = '';
    for (final pData in root.querySelectorAll('p.data')) {
      String currentLabel = '';
      final currentTags = <DetailTag>[];
      void saveGroup() {
        if (currentLabel.isEmpty && currentTags.isEmpty) return;
        if (currentLabel.contains('更新') && currentTags.isEmpty) {
          updateText = cleanText(pData.text);
        } else if (currentTags.isNotEmpty) {
          tagGroups.add(TagGroup(label: currentLabel, tags: List.of(currentTags)));
        }
        currentTags.clear();
      }

      for (final child in pData.nodes) {
        if (child is! Element) continue;
        if (child.localName == 'span' &&
            child.classes.contains('text-muted')) {
          saveGroup();
          currentLabel = cleanText(child.text);
        } else if (child.localName == 'a') {
          final title = cleanText(child.text);
          if (title.isNotEmpty && !title.contains('未知')) {
            currentTags.add(
                DetailTag(title, absolutize(child.attributes['href'] ?? '', base)));
          }
        }
      }
      saveGroup();
    }

    return MediaDetail(
      title: title.isEmpty ? '未知标题' : title,
      url: absolutize(url, base),
      poster: absolutize(attrOf(root, 'div.v_sd_l img', 'src'), base),
      summary: textOf(root, 'div.v_cont'),
      score: textOf(root, 'span.data-favs-num'),
      updateText: updateText,
      tagGroups: tagGroups,
      tags: tagGroups.expand((g) => g.tags).toList(),
      groups: groups,
      recommendations: recommendations,
    );
  }

  @override
  List<Episode> parseCurrentEpisodes(
    Document document,
    AppSettings settings,
    int groupIndex,
    String currentUrl,
  ) {
    final base = domain(settings);
    return document
        .querySelectorAll('a')
        .map((a) {
          return Episode(
              title: cleanText(a.text),
              url: absolutize(a.attributes['href'] ?? '', base));
        })
        .where((episode) =>
            episode.title.isNotEmpty && episode.url.contains('play'))
        .toList();
  }

  @override
  List<PlayItem> parsePlayItems(Document document, AppSettings settings) {
    final items = super.parsePlayItems(document, settings);
    if (items.isNotEmpty) return items;
    final iframe = document.querySelector('iframe')?.attributes['src'] ?? '';
    if (iframe.startsWith('http') &&
        (iframe.contains('.m3u8') || iframe.contains('.mp4'))) {
      return [
        PlayItem(
            url: iframe,
            type: iframe.contains('.m3u8') ? PlayType.m3u8 : PlayType.mp4)
      ];
    }
    return const [];
  }

  @override
  Future<List<PlayItem>> loadPlayItems(
    MoviesHttpClient client,
    AppSettings settings,
    String episodeUrl,
  ) async {
    final resolved = episodePageUrl(settings, episodeUrl);
    final encrypted = await client.postForm(
      resolved,
      const {'player': 'sili'},
      headers: requestHeaders(settings),
    );
    final decoded = silisiliDecodeData(encrypted);
    if (decoded.isEmpty) return const [];
    final url = silisiliExtractPlayUrl(decoded);
    if (url.isEmpty) return const [];
    final lower = url.toLowerCase();
    final type = lower.contains('.m3u8')
        ? PlayType.m3u8
        : lower.contains('.mp4')
            ? PlayType.mp4
            : PlayType.other;
    return [PlayItem(url: url, type: type, headers: playerHeaders(settings))];
  }

  List<MediaItem> _listItems(Document document, String base) {
    final roots = document.querySelectorAll(
        'article.article, article.post-list, div.topic-item a, div.search-image > a, div.sliderli a');
    return roots
        .map((e) {
          final link = e.localName == 'a' ? e : e.querySelector('a');
          // Remove badge spans (new/推荐/热门) before extracting title text
          final titleNode = e.querySelector('h2.entry-title');
          titleNode?.querySelectorAll('span.badge').forEach((s) => s.remove());
          return MediaItem(
            title: firstNonEmpty([
              link?.attributes['title'] ?? '',
              cleanText(titleNode?.text ?? ''),
              textOf(e, 'div.list-body'),
              textOf(e, 'span.tit'),
            ]),
            url: absolutize(link?.attributes['href'] ?? '', base),
            poster: firstNonEmpty([
              imageFromElement(e, base),
              absolutize(_cssImage(attrOf(e, 'i.thumb', 'style')), base),
            ]),
            subtitle: textOf(e, '.entry-meta, time, .score'),
            sourceId: source.id,
          );
        })
        .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
        .toList();
  }
}

String _cssImage(String value) {
  return RegExp(r'https?:[^) ;]+').firstMatch(value)?.group(0) ?? value;
}

bool _isHiddenPlaySource(String title) {
  final normalized = cleanText(title).toLowerCase().replaceAll(
        RegExp(r'\s+'),
        '',
      );
  return normalized == 'no.s';
}
