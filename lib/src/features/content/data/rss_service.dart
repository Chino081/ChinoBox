import 'package:xml/xml.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/movies_http_client.dart';
import '../domain/content_models.dart';

class RssService {
  RssService(this._client);

  final MoviesHttpClient _client;

  Future<List<RssItem>> fetchRss(String baseUrl, String rssPath) async {
    final url = '$baseUrl$rssPath';
    try {
      final body = await _client.getText(url);
      return _parse(body);
    } catch (e) {
      AppLogger.warn('RSS 获取失败: $url — $e');
      return const [];
    }
  }

  List<RssItem> _parse(String xmlStr) {
    try {
      final document = XmlDocument.parse(xmlStr);
      final items = document.findAllElements('item');
      final result = <RssItem>[];
      for (final item in items) {
        final title = _text(item, 'title');
        final link = _text(item, 'link');
        if (title.isEmpty || link.isEmpty) continue;
        result.add(RssItem(
          title: title,
          link: link,
          description: _text(item, 'description'),
          pubDate: _parseDate(_text(item, 'pubDate')),
        ));
      }
      result.sort((a, b) {
        if (a.pubDate == null || b.pubDate == null) return 0;
        return b.pubDate!.compareTo(a.pubDate!);
      });
      return result;
    } catch (e) {
      AppLogger.warn('RSS 解析失败: $e');
      return const [];
    }
  }

  static String _text(XmlElement parent, String tag) {
    final el = parent.findElements(tag).firstOrNull;
    return el?.innerText.trim() ?? '';
  }

  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
