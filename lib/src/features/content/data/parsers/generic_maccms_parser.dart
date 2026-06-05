import 'package:html/dom.dart';

import '../../../settings/app_settings.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
import '../site_parser.dart';

class GenericMaccmsParser extends SiteParser {
  GenericMaccmsParser(
    super.source, {
    this.searchTemplate = '/search/%s----------%p---.html',
    this.categoryTemplate = '/show/%s--------%p---.html',
    this.itemSelector =
        'ul.stui-vodlist li a, a.stui-vodlist__thumb, a.lazyload, .module-item-pic a, .module-card-item-poster',
  });

  final String searchTemplate;
  final String categoryTemplate;
  final String itemSelector;

  @override
  bool get needsProxy => false;

  @override
  Map<String, String> requestHeaders(AppSettings settings) => {
        'Referer': domain(settings),
      };

  @override
  List<CategoryGroup> get categories => const [
        CategoryGroup(
          title: '类型',
          options: [
            CategoryOption(title: '电影', path: '1'),
            CategoryOption(title: '电视剧', path: '2'),
            CategoryOption(title: '综艺', path: '3'),
            CategoryOption(title: '动漫', path: '4'),
          ],
        ),
      ];

  @override
  String searchUrl(AppSettings settings, String query, int page) {
    final encoded = Uri.encodeComponent(query);
    return domain(settings) +
        searchTemplate.replaceAll('%s', encoded).replaceAll('%p', '$page');
  }

  @override
  String categoryUrl(AppSettings settings, String path, int page) {
    return domain(settings) +
        categoryTemplate.replaceAll('%s', path).replaceAll('%p', '$page');
  }

  @override
  List<HomeSection> parseHome(Document document, AppSettings settings) {
    final base = domain(settings);
    final sections = <HomeSection>[];
    final panels =
        document.querySelectorAll('.stui-pannel, .module, .box, section');
    for (final panel in panels) {
      final items = _parseItems(panel, base);
      if (items.length < 2) continue;
      final title = firstNonEmpty([
        textOf(panel, '.stui-pannel__head h3'),
        textOf(panel, '.module-heading h2'),
        textOf(panel, '.module-title'),
        textOf(panel, 'h2'),
        textOf(panel, 'h3'),
      ]);
      sections
          .add(HomeSection(title: title.isEmpty ? '推荐' : title, items: items));
    }
    if (sections.isNotEmpty) return dedupeSections(sections);

    final items = _parseItems(rootElement(document), base);
    if (items.isEmpty) return const [];
    return [HomeSection(title: '推荐', items: items.take(36).toList())];
  }

  @override
  List<MediaItem> parseList(Document document, AppSettings settings) {
    return _parseItems(rootElement(document), domain(settings));
  }

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    final base = domain(settings);
    final root = rootElement(document);
    final title = firstNonEmpty([
      textOf(root, '.stui-content__detail h1'),
      textOf(root, '.module-info-heading h1'),
      textOf(root, 'h1'),
    ]);
    final poster = firstNonEmpty([
      imageFromElement(
          root.querySelector('.stui-content__thumb') ?? root, base),
      imageFromElement(root.querySelector('.module-info-poster') ?? root, base),
    ]);
    final metadata = root
        .querySelectorAll(
            '.stui-content__detail p.data, .module-info-item, .data')
        .map((e) => cleanText(e.text))
        .where((e) => e.isNotEmpty)
        .take(8)
        .toList();
    final summary = firstNonEmpty([
      textOf(root, '.stui-content__detail p.desc'),
      textOf(root, '.module-info-introduction-content'),
      textOf(root, '.desc'),
      textOf(root, '.sketch'),
    ]);
    final groups = _parseEpisodeGroups(root, base);
    final recommendations = _parseItems(root, base)
        .where((item) => item.url != absolutize(url, base))
        .take(12)
        .toList();
    return MediaDetail(
      title: title.isEmpty ? '未知标题' : title,
      url: absolutize(url, base),
      poster: poster,
      summary: summary,
      score: textOf(root, '.score, .fraction, .rating'),
      metadata: metadata,
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
    final groups = _parseEpisodeGroups(rootElement(document), domain(settings));
    if (groupIndex >= 0 && groupIndex < groups.length) {
      return groups[groupIndex].episodes;
    }
    return groups.expand((group) => group.episodes).toList();
  }

  List<MediaItem> _parseItems(Element root, String base) {
    final result = <MediaItem>[];
    final seen = <String>{};
    for (final element in root.querySelectorAll(itemSelector)) {
      final href = element.attributes['href'] ?? attrOf(element, 'a', 'href');
      if (href.isEmpty) continue;
      final url = absolutize(href, base);
      if (seen.contains(url)) continue;
      final title = firstNonEmpty([
        element.attributes['title'] ?? '',
        textOf(element, '.title'),
        textOf(element, '.module-item-title'),
        textOf(element, '.stui-vodlist__title'),
        cleanText(element.text),
      ]);
      if (title.isEmpty) continue;
      seen.add(url);
      result.add(
        MediaItem(
          title: title,
          url: url,
          poster: imageFromElement(element, base),
          subtitle: firstNonEmpty([
            textOf(element, '.text-right'),
            textOf(element, '.module-item-note'),
            textOf(element, '.pic-text'),
            textOf(element, '.note'),
          ]),
          sourceId: source.id,
        ),
      );
    }
    return result;
  }

  List<EpisodeGroup> _parseEpisodeGroups(Element root, String base) {
    final groups = <EpisodeGroup>[];
    final headings = root.querySelectorAll(
      '.stui-vodlist__head, .module-tab-item, .module-tab-name, .play-tab li a',
    );
    final lists = root.querySelectorAll(
      '.stui-content__playlist, .module-play-list, .stui-play__list, .play-content ul',
    );
    for (var i = 0; i < lists.length; i++) {
      final title =
          i < headings.length ? cleanText(headings[i].text) : '播放源 ${i + 1}';
      final episodes = _episodeAnchors(lists[i], base);
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(
            title: title.isEmpty ? '播放源 ${i + 1}' : title, episodes: episodes));
      }
    }
    if (groups.isEmpty) {
      final episodes = _episodeAnchors(root, base);
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(title: '播放列表', episodes: episodes));
      }
    }
    return groups;
  }

  List<Episode> _episodeAnchors(Element root, String base) {
    final episodes = <Episode>[];
    final seen = <String>{};
    for (final a in root.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final text = cleanText(a.text);
      if (text.isEmpty) continue;
      final looksEpisode =
          RegExp(r'(第|集|话|HD|BD|正片|播放|^\d+$)', caseSensitive: false)
              .hasMatch(text);
      if (!looksEpisode && !href.contains('play')) continue;
      final url = absolutize(href, base);
      if (seen.add(url)) episodes.add(Episode(title: text, url: url));
    }
    return episodes;
  }
}
