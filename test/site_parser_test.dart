import 'package:chinobox/src/features/content/data/parsers/girigirilove_parser.dart';
import 'package:chinobox/src/features/content/data/parsers/tbys_parser.dart';
import 'package:chinobox/src/features/content/data/site_parser.dart';
import 'package:chinobox/src/features/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  group('TbysParser', () {
    test('parses current card and detail layouts', () {
      final parser = TbysParser();
      final settings = AppSettings.defaults();
      final list = parser.parseList(
        html_parser.parse('''
          <div class="columns vod-list">
            <div class="column">
              <a href="/index.php/vod/detail/id/325138.html"
                 class="card vod-list-item" title="九龙城寨之围城粤语">
                <img src="placeholder.gif"
                     data-src="//cdn.yansk.cn/upload/poster.jpg">
                <div class="vod-info-box">
                  <div class="subtitle is-6">九龙城寨之围城粤语</div>
                  <div class="subtitle is-7">动作片简介</div>
                </div>
                <div class="card-content">
                  <p class="title is-6">九龙城寨之围城粤语</p>
                  <p class="subtitle is-6">正片</p>
                </div>
              </a>
            </div>
          </div>
        '''),
        settings,
      );

      expect(list, hasLength(1));
      expect(list.first.title, '九龙城寨之围城粤语');
      expect(list.first.poster, 'https://cdn.yansk.cn/upload/poster.jpg');
      expect(list.first.subtitle, '正片');

      final detail = parser.parseDetail(
        html_parser.parse('''
          <div class="column"><div class="box">
            <img alt="九龙城寨之围城粤语" src="//cdn.yansk.cn/upload/poster.jpg">
          </div></div>
          <div class="column">
            <div class="is-horizontal">更新：2026-06-01</div>
            <div class="is-horizontal">导演：郑保瑞</div>
            <div class="is-horizontal">简介：城寨故事</div>
          </div>
          <div class="tags"><a href="/index.php/vod/search/class/动作.html">动作</a></div>
          <div class="play-source-box">
            <div class="tabs"><ul><li data-tab="play-tab-1">ikm3u8</li></ul></div>
            <div class="tab-body-item" data-tab="play-tab-1">
              <a href="/index.php/vod/play/id/325138/sid/1/nid/1.html">正片</a>
            </div>
          </div>
        '''),
        settings,
        '/index.php/vod/detail/id/325138.html',
      );

      expect(detail.title, '九龙城寨之围城粤语');
      expect(detail.summary, '城寨故事');
      expect(detail.groups.single.title, 'ikm3u8');
      expect(detail.groups.single.episodes.single.title, '正片');
    });
  });

  group('GiriGiriLoveParser', () {
    test('parses current public list and anthology layouts', () {
      final parser = GiriGiriLoveParser();
      final settings = AppSettings.defaults();
      final list = parser.parseList(
        html_parser.parse('''
          <div class="public-list-box public-pic-b">
            <a class="public-list-exp" href="/GV27016/" title="木头风纪委员和迷你裙JK的故事">
              <img data-src="/upload/vod/poster.webp">
              <span class="public-list-prb">更新至09集</span>
            </a>
            <a class="time-title" href="/GV27016/">木头风纪委员和迷你裙JK的故事</a>
            <div class="public-list-subtitle">青春故事</div>
          </div>
        '''),
        settings,
      );

      expect(list, hasLength(1));
      expect(list.first.title, '木头风纪委员和迷你裙JK的故事');
      expect(list.first.poster,
          'https://ani.girigirilove.com/upload/vod/poster.webp');
      expect(list.first.subtitle, '更新至09集');

      final detail = parser.parseDetail(
        html_parser.parse('''
          <h3 class="slide-info-title">木头风纪委员和迷你裙JK的故事</h3>
          <div class="detail-pic"><img data-src="/upload/vod/poster.webp"></div>
          <span class="slide-info-remarks cor5">更新至09集</span>
          <div class="play-score"><div class="fraction">9.5</div></div>
          <div id="height_limit">简介文本</div>
          <div class="anthology">
            <div class="anthology-tab">
              <div class="swiper-wrapper"><a>繁中<span class="badge">8</span></a></div>
            </div>
            <ul class="anthology-list-play">
              <li><a href="/playGV27016-1-1/">01</a></li>
              <li><a href="/playGV27016-1-2/">02</a></li>
            </ul>
          </div>
        '''),
        settings,
        '/GV27016/',
      );

      expect(detail.title, '木头风纪委员和迷你裙JK的故事');
      expect(detail.score, '9.5');
      expect(detail.groups.single.title, '繁中');
      expect(detail.groups.single.episodes, hasLength(2));
    });
  });

  test('decodes encrypted player_aaaa m3u8 urls', () {
    final items = extractDirectPlayItems('''
      <script>
      var player_aaaa = {"encrypt":2,
        "url":"JTY4JTc0JTc0JTcwJTczJTNBJTJGJTJGJTY1JTc4JTYxJTZEJTcwJTZDJTY1JTJFJTYzJTZGJTZEJTJGJTYxJTJGJTcwJTZDJTYxJTc5JTZDJTY5JTczJTc0JTJFJTZEJTMzJTc1JTM4"};
      </script>
    ''');

    expect(items, hasLength(1));
    expect(items.first.url, 'https://example.com/a/playlist.m3u8');
  });
}
