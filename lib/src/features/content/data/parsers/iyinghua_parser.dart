import 'package:html/dom.dart';

import '../../../settings/app_settings.dart';
import '../../../source/domain/source_catalog.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
import 'generic_maccms_parser.dart';

class IYingHuaParser extends GenericMaccmsParser {
  IYingHuaParser()
      : super(
          sourceById('iyinghua'),
          searchTemplate: '/search.php?searchword=%s',
        );

  @override
  List<CategoryGroup> get categories => const [
        CategoryGroup(
          title: '分类',
          options: [
            CategoryOption(title: '国产动漫', path: '/dm/1.html'),
            CategoryOption(title: '日本动漫', path: '/dm/2.html'),
            CategoryOption(title: '欧美动漫', path: '/dm/3.html'),
            CategoryOption(title: '港台动漫', path: '/dm/4.html'),
            CategoryOption(title: '海外动漫', path: '/dm/5.html'),
            CategoryOption(title: '动画片', path: '/dm/6.html'),
          ],
        ),
      ];

  @override
  String categoryUrl(AppSettings settings, String path, int page) {
    if (page <= 1) return absolutize(path, domain(settings));
    return absolutize(
        path.replaceFirst('.html', '-$page.html'), domain(settings));
  }

  @override
  MediaDetail parseDetail(Document document, AppSettings settings, String url) {
    final detail = super.parseDetail(document, settings, url);
    final base = domain(settings);
    final root = document.body ?? document.documentElement!;
    final groups = <EpisodeGroup>[];
    for (final list in root
        .querySelectorAll('.movurl, .playlist, .play-list, .paly_list_btn')) {
      final episodes = list
          .querySelectorAll('a')
          .map((a) {
            return Episode(
                title: cleanText(a.text),
                url: absolutize(a.attributes['href'] ?? '', base));
          })
          .where(
              (episode) => episode.title.isNotEmpty && episode.url.isNotEmpty)
          .toList();
      if (episodes.isNotEmpty) {
        groups.add(EpisodeGroup(
            title: '播放源 ${groups.length + 1}', episodes: episodes));
      }
    }
    return MediaDetail(
      title: detail.title,
      url: detail.url,
      poster: detail.poster,
      summary: detail.summary,
      score: detail.score,
      metadata: detail.metadata,
      tags: detail.tags,
      groups: groups.isEmpty ? detail.groups : groups,
      recommendations: detail.recommendations,
    );
  }
}
