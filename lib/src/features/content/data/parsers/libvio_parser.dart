import 'package:html/dom.dart';

import '../../../settings/app_settings.dart';
import '../../../source/domain/source_catalog.dart';
import '../../domain/content_models.dart';
import '../html_helpers.dart';
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

    if (groups.isEmpty) {
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
}
