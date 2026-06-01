import 'package:html/dom.dart';

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
            CategoryOption(title: '电影', path: '/s/dianying'),
            CategoryOption(title: '剧集', path: '/s/dianshiju'),
            CategoryOption(title: '动漫', path: '/s/dongman'),
          ],
        ),
      ];

  @override
  String searchUrl(AppSettings settings, String query, int page) {
    return '${domain(settings)}/search/${Uri.encodeComponent(query)}/$page';
  }

  @override
  String categoryUrl(AppSettings settings, String path, int page) {
    return '${domain(settings)}$path/$page';
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
    final groups = root
        .querySelectorAll('.play-item, .btn-group')
        .map((list) {
          final episodes = list
              .querySelectorAll('a')
              .map((a) {
                return Episode(
                    title: cleanText(a.text),
                    url: absolutize(a.attributes['href'] ?? '', base));
              })
              .where((episode) =>
                  episode.title.isNotEmpty && episode.url.isNotEmpty)
              .toList();
          return EpisodeGroup(title: '播放源', episodes: episodes);
        })
        .where((group) => group.episodes.isNotEmpty)
        .toList();

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
}
