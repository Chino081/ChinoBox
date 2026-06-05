import 'package:html/dom.dart';

import '../../../settings/app_settings.dart';
import '../../../source/domain/source_catalog.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
import 'generic_maccms_parser.dart';

class TbysParser extends GenericMaccmsParser {
  TbysParser()
      : super(
          sourceById('tbys'),
          searchTemplate: '/index.php/vod/search/page/%p/wd/%s.html',
          categoryTemplate: '/index.php/vod/show/id/%s/page/%p.html',
        );

  @override
  List<HomeSection> parseHome(Document document, AppSettings settings) {
    final base = domain(settings);
    final sections = <HomeSection>[];

    final banners = _parseBannerItems(document, base);
    if (banners.isNotEmpty) {
      sections.add(HomeSection(title: '影视推荐', items: banners));
    }

    final defaultTitles = ['热门电影', '电影', '连续剧', '综艺', '动画'];
    final lists = document.querySelectorAll('div.vod-list');
    for (var i = 0; i < lists.length; i++) {
      final items = _parseVodCards(lists[i], base);
      if (items.isEmpty) continue;
      final sectionRoot = _sectionRoot(lists[i]);
      final title = firstNonEmpty([
        textOf(sectionRoot, '.level .title'),
        i < defaultTitles.length ? defaultTitles[i] : '',
      ]);
      sections
          .add(HomeSection(title: title.isEmpty ? '推荐' : title, items: items));
    }

    if (sections.isNotEmpty) return dedupeSections(sections);
    final fallback = _parseVodCards(rootElement(document), base);
    return fallback.isEmpty
        ? const []
        : [HomeSection(title: '推荐', items: fallback.take(36).toList())];
  }

  @override
  List<MediaItem> parseList(Document document, AppSettings settings) {
    final base = domain(settings);
    final cards = _parseVodCards(rootElement(document), base);
    if (cards.isNotEmpty) return cards;
    return _parseSearchItems(rootElement(document), base);
  }

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    final base = domain(settings);
    final root = rootElement(document);
    final resolved = absolutize(url, base);
    final title = firstNonEmpty([
      attrOf(root, '.column .box img', 'alt'),
      textOf(root, 'h1'),
      textOf(root, '.title'),
    ]);
    final poster =
        imageFromElement(root.querySelector('.column .box') ?? root, base);
    final infoElements = root.querySelectorAll('.column .is-horizontal');
    final metadata = infoElements
        .map((e) => cleanText(e.text))
        .where((text) => text.isNotEmpty && !text.contains('简介'))
        .take(8)
        .toList();
    final summary = firstNonEmpty([
      for (final info in infoElements)
        cleanText(info.text).contains('简介') ? _stripLabel(info.text) : '',
      textOf(root, '.content .sketch'),
    ]);
    final updateText = firstNonEmpty([
      for (final info in infoElements)
        cleanText(info.text).contains('更新') ? _stripLabel(info.text) : '',
    ]);

    return MediaDetail(
      title: title.isEmpty ? '未知标题' : title,
      url: resolved,
      poster: poster,
      summary: summary,
      updateText: updateText,
      metadata: metadata,
      tags: _parseTags(root, base),
      groups: _parseEpisodeGroups(root, base),
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
    final groups = _parseEpisodeGroups(rootElement(document), domain(settings));
    if (groupIndex >= 0 && groupIndex < groups.length) {
      return groups[groupIndex].episodes;
    }
    return groups.expand((group) => group.episodes).toList();
  }

  List<MediaItem> _parseBannerItems(Document document, String base) {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final anchor
        in document.querySelectorAll('.carousel-wrapper .swiper-slide a')) {
      final item = _itemFromAnchor(anchor, base);
      if (item != null && seen.add(item.url)) items.add(item);
    }
    return items.take(12).toList();
  }

  List<MediaItem> _parseVodCards(Element root, String base) {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final anchor in root.querySelectorAll('a.card.vod-list-item')) {
      final item = _itemFromAnchor(anchor, base);
      if (item != null && seen.add(item.url)) items.add(item);
    }
    return items;
  }

  List<MediaItem> _parseSearchItems(Element root, String base) {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final box
        in root.querySelectorAll('.search-vod-list .vod-detail-box')) {
      final anchor = box.querySelector('a.title[href]') ??
          box.querySelector('a[href*="/vod/detail/"]') ??
          box.querySelector('a[href]');
      if (anchor == null) continue;
      final item = _itemFromAnchor(anchor, base, context: box);
      if (item != null && seen.add(item.url)) items.add(item);
    }
    return items;
  }

  MediaItem? _itemFromAnchor(
    Element anchor,
    String base, {
    Element? context,
  }) {
    final root = context ?? anchor;
    final href = anchor.attributes['href'] ?? '';
    if (href.isEmpty || href.startsWith('javascript:')) return null;
    final title = firstNonEmpty([
      anchor.attributes['title'] ?? '',
      textOf(root, '.card-content .title'),
      textOf(root, '.vod-info-box .subtitle.is-6'),
      cleanText(anchor.text),
    ]);
    if (title.isEmpty) return null;
    return MediaItem(
      title: title,
      url: absolutize(href, base),
      poster: imageFromElement(root, base),
      subtitle: firstNonEmpty([
        textOf(root, '.card-content .subtitle'),
        textOf(root, '.vod-tagsinfo'),
      ]),
      summary: textOf(root, '.vod-info-box .subtitle.is-7'),
      sourceId: source.id,
    );
  }

  List<DetailTag> _parseTags(Element root, String base) {
    final tags = <DetailTag>[];
    for (final anchor in root.querySelectorAll('.tags a[href]')) {
      final title = cleanText(anchor.text);
      final href = anchor.attributes['href'] ?? '';
      if (title.isNotEmpty && href.isNotEmpty) {
        tags.add(DetailTag(title, absolutize(href, base)));
      }
    }
    return tags;
  }

  List<EpisodeGroup> _parseEpisodeGroups(Element root, String base) {
    final container = root.querySelector('.play-source-box') ??
        root.querySelector('.play-list-box') ??
        root;
    final headings = container.querySelectorAll('.tabs ul li[data-tab]');
    final groups = <EpisodeGroup>[];
    for (var i = 0; i < headings.length; i++) {
      final tab = headings[i].attributes['data-tab'] ?? '';
      if (tab.isEmpty) continue;
      final listRoot = container.querySelector(
            '.tab-body-item[data-tab="$tab"], [data-tab="$tab"].tab-body-item',
          ) ??
          root.querySelector(
            '.tab-body-item[data-tab="$tab"], [data-tab="$tab"].tab-body-item',
          );
      final episodes = _parseEpisodeAnchors(listRoot ?? container, base);
      if (episodes.isNotEmpty) {
        final title = cleanText(headings[i].text);
        groups.add(
          EpisodeGroup(
            title: title.isEmpty ? '播放源 ${i + 1}' : title,
            episodes: episodes,
          ),
        );
      }
    }

    if (groups.isEmpty) {
      final episodes = _parseEpisodeAnchors(root, base);
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(title: '播放列表', episodes: episodes));
      }
    }
    return groups;
  }

  List<Episode> _parseEpisodeAnchors(Element root, String base) {
    final episodes = <Episode>[];
    final seen = <String>{};
    for (final anchor in root.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!href.contains('/vod/play/')) continue;
      final title = cleanText(anchor.text);
      if (title.isEmpty) continue;
      final url = absolutize(href, base);
      if (seen.add(url)) episodes.add(Episode(title: title, url: url));
    }
    return episodes;
  }
}

Element _sectionRoot(Element element) {
  var current = element.parent;
  while (current != null) {
    if (current.classes.contains('section')) return current;
    current = current.parent;
  }
  return element.parent ?? element;
}

String _stripLabel(String value) {
  return cleanText(value).replaceFirst(RegExp(r'^[^:：]{1,12}[:：]\s*'), '');
}
