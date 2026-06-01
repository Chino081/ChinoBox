import 'package:html/dom.dart';

import '../../../../core/network/movies_http_client.dart';
import '../../../settings/app_settings.dart';
import '../../../source/domain/source_catalog.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
import 'generic_maccms_parser.dart';

class GiriGiriLoveParser extends GenericMaccmsParser {
  GiriGiriLoveParser()
      : super(
          sourceById('girigirilove'),
          searchTemplate: '/search/%s----------%p---/',
          categoryTemplate: '/show/%s--------%p---/',
        );

  @override
  Map<String, String> requestHeaders(AppSettings settings) => {
        'Origin': domain(settings),
        'Referer': '${domain(settings)}/',
      };

  @override
  String? searchCaptchaImageUrl(
    Document document,
    AppSettings settings,
    String responseUrl,
  ) {
    final root = _root(document);
    final input = root.querySelector('input[name="verify"], .ds-verify');
    final image = root.querySelector('img.ds-verify-img, img[src*="/verify/"]');
    if (input == null || image == null) return null;
    final src = image.attributes['src'] ?? '';
    if (src.isEmpty) return null;
    return absolutize(src, domain(settings));
  }

  @override
  Future<String?> loadVerifiedSearchBody(
    MoviesHttpClient client,
    AppSettings settings,
    String query,
    int page,
    String code,
  ) async {
    final search = searchUrl(settings, query, page);
    final verifyUrl = Uri.parse(domain(settings)).replace(
      path: '/index.php/ajax/verify_check',
      queryParameters: {
        'type': 'search',
        'verify': code,
      },
    ).toString();
    final headers = {
      ...requestHeaders(settings),
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Referer': search,
      'X-Requested-With': 'XMLHttpRequest',
    };
    await client.postForm(verifyUrl, const {}, headers: headers);
    return client.getText(search, headers: requestHeaders(settings));
  }

  @override
  List<CategoryGroup> get categories => const [
        CategoryGroup(
          title: '频道',
          options: [
            CategoryOption(title: '日番', path: '2'),
            CategoryOption(title: '美番', path: '3'),
            CategoryOption(title: '剧场版', path: '21'),
            CategoryOption(title: '真人番剧', path: '20'),
            CategoryOption(title: 'BD副音轨', path: '24'),
            CategoryOption(title: '其他', path: '26'),
          ],
        ),
      ];

  @override
  List<HomeSection> parseHome(Document document, AppSettings settings) {
    final base = domain(settings);
    final sections = <HomeSection>[];

    final banners = _parseBannerItems(document, base);
    if (banners.isNotEmpty) {
      sections.add(HomeSection(title: '动漫推荐', items: banners));
    }

    for (final box in document.querySelectorAll('.box-width.wow.fadeInUp')) {
      if (box.id == 'week-module-box') continue;
      final items = _parsePublicItems(box, base)
          .where((item) => item.url.contains('/GV'))
          .toList();
      if (items.isEmpty) continue;
      final title = textOf(box, 'h4.title-h');
      sections.add(
        HomeSection(
          title: title.isEmpty ? '推荐' : title,
          items: items,
          moreUrl: absolutize(attrOf(box, '.title-right a', 'href'), base),
        ),
      );
    }

    if (sections.isNotEmpty) return _dedupeSections(sections);
    final fallback = _parsePublicItems(_root(document), base);
    return fallback.isEmpty
        ? const []
        : [HomeSection(title: '推荐', items: fallback.take(36).toList())];
  }

  @override
  List<MediaItem> parseList(Document document, AppSettings settings) {
    final base = domain(settings);
    final root = _root(document);
    final searchItems = _parseSearchItems(root, base);
    if (searchItems.isNotEmpty) return searchItems;
    return _parsePublicItems(root, base);
  }

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    final base = domain(settings);
    final root = _root(document);
    final resolved = absolutize(url, base);
    final title = firstNonEmpty([
      textOf(root, 'h3.slide-info-title'),
      textOf(root, 'h1'),
      attrOf(root, 'div.detail-pic img', 'alt'),
    ]);
    final metadata = root
        .querySelectorAll('.slide-info, .info-parameter li')
        .map((e) => cleanText(e.text))
        .where((text) =>
            text.isNotEmpty && !text.contains('简介') && !text.contains('片名'))
        .take(10)
        .toList();

    return MediaDetail(
      title: title.isEmpty ? '未知标题' : title,
      url: resolved,
      poster:
          imageFromElement(root.querySelector('div.detail-pic') ?? root, base),
      summary: textOf(root, '#height_limit'),
      score: firstNonEmpty([
        textOf(root, 'div.play-score .fraction'),
        textOf(root, 'div.play-score'),
      ]),
      updateText: textOf(root, 'span.slide-info-remarks.cor5'),
      metadata: metadata,
      tags: _parseTags(root, base),
      groups: _parseEpisodeGroups(root, base),
      recommendations: _parsePublicItems(root, base)
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
    final groups = _parseEpisodeGroups(_root(document), domain(settings));
    if (groupIndex >= 0 && groupIndex < groups.length) {
      return groups[groupIndex].episodes;
    }
    return groups.expand((group) => group.episodes).toList();
  }

  List<MediaItem> _parseBannerItems(Document document, String base) {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final slide
        in document.querySelectorAll('div.swiper-wrapper > .slide-time-bj')) {
      final anchor = slide.querySelector('a[href]');
      if (anchor == null) continue;
      final item = _itemFromPublicBox(slide, base, anchor: anchor);
      if (item != null && seen.add(item.url)) items.add(item);
    }
    return items.take(12).toList();
  }

  List<MediaItem> _parseSearchItems(Element root, String base) {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final box in root.querySelectorAll('div.search-list')) {
      final anchor = box.querySelector('div.detail-info > a[href]') ??
          box.querySelector('a[href*="/GV"]') ??
          box.querySelector('a[href]');
      if (anchor == null) continue;
      final item = _itemFromPublicBox(box, base, anchor: anchor);
      if (item != null && seen.add(item.url)) items.add(item);
    }
    return items;
  }

  List<MediaItem> _parsePublicItems(Element root, String base) {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (final box in root.querySelectorAll('div.public-list-box')) {
      final item = _itemFromPublicBox(box, base);
      if (item != null && seen.add(item.url)) items.add(item);
    }
    return items;
  }

  MediaItem? _itemFromPublicBox(
    Element box,
    String base, {
    Element? anchor,
  }) {
    final link = anchor ??
        box.querySelector('a.time-title[href]') ??
        box.querySelector('a.public-list-exp[href]') ??
        box.querySelector('a[href*="/GV"]') ??
        box.querySelector('a[href]');
    final href = link?.attributes['href'] ?? '';
    if (href.isEmpty || href.startsWith('javascript:')) return null;
    final title = firstNonEmpty([
      textOf(box, 'h3.slide-info-title'),
      textOf(box, 'a.time-title'),
      link?.attributes['title'] ?? '',
      attrOf(box, 'a.public-list-exp', 'title'),
      textOf(box, '.thumb-content .thumb-txt'),
      cleanText(link?.text ?? ''),
    ]);
    if (title.isEmpty) return null;
    return MediaItem(
      title: title,
      url: absolutize(href, base),
      poster: imageFromElement(box, base),
      subtitle: firstNonEmpty([
        textOf(box, 'span.public-list-prb'),
        textOf(box, 'span.slide-info-remarks'),
        textOf(box, '.slide-info'),
      ]),
      summary: firstNonEmpty([
        textOf(box, '.public-list-subtitle'),
        textOf(box, '.slide-info.hide2'),
      ]),
      sourceId: source.id,
    );
  }

  List<DetailTag> _parseTags(Element root, String base) {
    final tags = <DetailTag>[];
    final seen = <String>{};
    for (final anchor
        in root.querySelectorAll('div.slide-info a, div.vod-tag a')) {
      final title = cleanText(anchor.text);
      if (title.isEmpty || !seen.add(title)) continue;
      final href = anchor.attributes['href'] ?? '';
      tags.add(DetailTag(title, href.isEmpty ? title : absolutize(href, base)));
    }
    return tags;
  }

  List<EpisodeGroup> _parseEpisodeGroups(Element root, String base) {
    final anthology = root.querySelector('div.anthology') ?? root;
    final titles =
        anthology.querySelectorAll('.anthology-tab .swiper-wrapper a');
    final lists = anthology.querySelectorAll('ul.anthology-list-play');
    final groups = <EpisodeGroup>[];
    for (var i = 0; i < lists.length; i++) {
      final episodes = _parseEpisodeAnchors(lists[i], base);
      if (episodes.isEmpty) continue;
      final title =
          i < titles.length ? _cleanGroupTitle(titles[i]) : '播放源 ${i + 1}';
      groups.add(EpisodeGroup(
        title: title.isEmpty ? '播放源 ${i + 1}' : title,
        episodes: episodes,
      ));
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
      if (!href.contains('playGV')) continue;
      final title = cleanText(anchor.text);
      if (title.isEmpty) continue;
      final url = absolutize(href, base);
      if (seen.add(url)) episodes.add(Episode(title: title, url: url));
    }
    return episodes;
  }
}

List<HomeSection> _dedupeSections(List<HomeSection> sections) {
  final seen = <String>{};
  return sections.where((section) => seen.add(section.title)).toList();
}

Element _root(Document document) {
  return document.body ?? document.documentElement ?? Element.tag('html');
}

String _cleanGroupTitle(Element element) {
  var title = cleanText(element.text);
  final badge = textOf(element, 'span.badge');
  if (badge.isNotEmpty) title = cleanText(title.replaceFirst(badge, ''));
  return title;
}
