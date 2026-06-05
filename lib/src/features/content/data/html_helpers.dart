import 'package:html/dom.dart';

import '../domain/content_models.dart';

String cleanText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String textOf(Element element, String selector) {
  return cleanText(element.querySelector(selector)?.text ?? '');
}

String attrOf(Element element, String selector, String attr) {
  return element.querySelector(selector)?.attributes[attr]?.trim() ?? '';
}

String absolutize(String url, String baseUrl) {
  final value = url.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  final base = Uri.parse(baseUrl);
  if (value.startsWith('//')) return '${base.scheme}:$value';
  return base.resolve(value).toString();
}

String firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final cleaned = cleanText(value);
    if (cleaned.isNotEmpty) return cleaned;
  }
  return '';
}

String firstAttr(Element element, List<String> selectors, String attr) {
  for (final selector in selectors) {
    final value = attrOf(element, selector, attr);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String imageFromElement(Element element, String baseUrl) {
  final raw = firstNonEmpty([
    element.attributes['data-original'] ?? '',
    element.attributes['data-src'] ?? '',
    element.attributes['data-background'] ?? '',
    element.attributes['src'] ?? '',
    element.attributes['style'] ?? '',
    attrOf(element, 'img', 'data-original'),
    attrOf(element, 'img', 'data-src'),
    attrOf(element, 'img', 'data-background'),
    attrOf(element, 'img', 'src'),
    attrOf(element, 'img', 'srcset').split(' ').first,
    attrOf(element, '[data-background]', 'data-background'),
    attrOf(element, '[style]', 'style'),
  ]);
  return absolutize(_extractCssUrl(raw), baseUrl);
}

String _extractCssUrl(String value) {
  final cssMatch =
      RegExp(r'''url\((["']?)(.*?)\1\)''').firstMatch(value.trim());
  if (cssMatch != null) return cssMatch.group(2) ?? value;
  final match = RegExp(r'https?:[^) ;]+').firstMatch(value);
  return match?.group(0) ?? value;
}

List<HomeSection> dedupeSections(List<HomeSection> sections) {
  final seen = <String>{};
  return sections.where((section) => seen.add(section.title)).toList();
}

Element rootElement(Document document) {
  return document.body ?? document.documentElement ?? Element.tag('html');
}

PlayType playTypeFor(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('.m3u8')) return PlayType.m3u8;
  if (lower.contains('.mp4')) return PlayType.mp4;
  return PlayType.other;
}
