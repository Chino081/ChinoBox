import 'dart:convert';

class PlayerEpisodeRef {
  const PlayerEpisodeRef({required this.title, required this.url});

  factory PlayerEpisodeRef.fromJson(Map<String, dynamic> json) {
    return PlayerEpisodeRef(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  final String title;
  final String url;
}

List<PlayerEpisodeRef> decodeEpisodes(String value) {
  if (value.isEmpty) return const [];
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(value)));
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) =>
            PlayerEpisodeRef.fromJson(Map<String, dynamic>.from(item)))
        .where((episode) => episode.title.isNotEmpty && episode.url.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}
