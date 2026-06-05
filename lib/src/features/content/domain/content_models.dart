class MediaItem {
  const MediaItem({
    required this.title,
    required this.url,
    this.poster = '',
    this.subtitle = '',
    this.summary = '',
    this.sourceId = '',
    this.previewUrl = '',
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      previewUrl: json['previewUrl'] as String? ?? '',
    );
  }

  final String title;
  final String url;
  final String poster;
  final String subtitle;
  final String summary;
  final String sourceId;
  final String previewUrl;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'poster': poster,
      'subtitle': subtitle,
      'summary': summary,
      'sourceId': sourceId,
      'previewUrl': previewUrl,
    };
  }
}

class HomeSection {
  const HomeSection({
    required this.title,
    required this.items,
    this.moreUrl = '',
    this.isBanner = false,
  });

  final String title;
  final List<MediaItem> items;
  final String moreUrl;
  final bool isBanner;
}

class CategoryOption {
  const CategoryOption({
    required this.title,
    required this.path,
  });

  final String title;
  final String path;
}

class CategoryGroup {
  const CategoryGroup({
    required this.title,
    required this.options,
  });

  final String title;
  final List<CategoryOption> options;
}

class DetailTag {
  const DetailTag(this.title, this.url);

  final String title;
  final String url;
}

class TagGroup {
  const TagGroup({required this.label, required this.tags});

  final String label;
  final List<DetailTag> tags;
}

class Episode {
  const Episode({
    required this.title,
    required this.url,
  });

  final String title;
  final String url;
}

class EpisodeGroup {
  const EpisodeGroup({
    required this.title,
    required this.episodes,
  });

  final String title;
  final List<Episode> episodes;
}

class MediaDetail {
  const MediaDetail({
    required this.title,
    required this.url,
    this.poster = '',
    this.summary = '',
    this.score = '',
    this.updateText = '',
    this.metadata = const [],
    this.tags = const [],
    this.tagGroups = const [],
    this.groups = const [],
    this.recommendations = const [],
  });

  final String title;
  final String url;
  final String poster;
  final String summary;
  final String score;
  final String updateText;
  final List<String> metadata;
  final List<DetailTag> tags;
  final List<TagGroup> tagGroups;
  final List<EpisodeGroup> groups;
  final List<MediaItem> recommendations;
}

enum PlayType { m3u8, mp4, other }

class PlayItem {
  const PlayItem({
    required this.url,
    required this.type,
    this.title = '',
    this.headers = const {},
  });

  final String url;
  final PlayType type;
  final String title;
  final Map<String, String> headers;
}

class FavoriteEntry {
  const FavoriteEntry({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.detailUrl,
    this.poster = '',
    this.summary = '',
    this.updatedAt = 0,
  });

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) {
    return FavoriteEntry(
      id: json['id'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      detailUrl: json['detailUrl'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }

  final String id;
  final String sourceId;
  final String title;
  final String detailUrl;
  final String poster;
  final String summary;
  final int updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceId': sourceId,
      'title': title,
      'detailUrl': detailUrl,
      'poster': poster,
      'summary': summary,
      'updatedAt': updatedAt,
    };
  }
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.detailUrl,
    required this.episodeTitle,
    required this.episodeUrl,
    required this.playUrl,
    this.playHeaders = const {},
    this.poster = '',
    this.position = 0,
    this.duration = 0,
    this.updatedAt = 0,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      detailUrl: json['detailUrl'] as String? ?? '',
      episodeTitle: json['episodeTitle'] as String? ?? '',
      episodeUrl: json['episodeUrl'] as String? ?? '',
      playUrl: json['playUrl'] as String? ?? '',
      playHeaders:
          Map<String, String>.from(json['playHeaders'] as Map? ?? const {}),
      poster: json['poster'] as String? ?? '',
      position: json['position'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }

  final String id;
  final String sourceId;
  final String title;
  final String detailUrl;
  final String episodeTitle;
  final String episodeUrl;
  final String playUrl;
  final Map<String, String> playHeaders;
  final String poster;
  final int position;
  final int duration;
  final int updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceId': sourceId,
      'title': title,
      'detailUrl': detailUrl,
      'episodeTitle': episodeTitle,
      'episodeUrl': episodeUrl,
      'playUrl': playUrl,
      'playHeaders': playHeaders,
      'poster': poster,
      'position': position,
      'duration': duration,
      'updatedAt': updatedAt,
    };
  }
}

class RssItem {
  const RssItem({
    required this.title,
    required this.link,
    this.description = '',
    this.pubDate,
    this.sourceName = '',
  });

  final String title;
  final String link;
  final String description;
  final DateTime? pubDate;
  final String sourceName;
}
