enum DownloadState { queued, downloading, paused, completed, failed }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.detailUrl,
    this.poster = '',
    this.addedAt = 0,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      detailUrl: json['detailUrl'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      addedAt: json['addedAt'] as int? ?? 0,
    );
  }

  final String id;
  final String sourceId;
  final String title;
  final String detailUrl;
  final String poster;
  final int addedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceId': sourceId,
      'title': title,
      'detailUrl': detailUrl,
      'poster': poster,
      'addedAt': addedAt,
    };
  }
}

class DownloadEpisode {
  const DownloadEpisode({
    required this.id,
    required this.taskId,
    required this.title,
    required this.episodeUrl,
    this.playUrl = '',
    this.playHeaders = const {},
    this.state = DownloadState.queued,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.localPath = '',
    this.addedAt = 0,
    this.errorMessage = '',
  });

  factory DownloadEpisode.fromJson(Map<String, dynamic> json) {
    final stateName = json['state'] as String? ?? 'queued';
    return DownloadEpisode(
      id: json['id'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      episodeUrl: json['episodeUrl'] as String? ?? '',
      playUrl: json['playUrl'] as String? ?? '',
      playHeaders:
          Map<String, String>.from(json['playHeaders'] as Map? ?? const {}),
      state: DownloadState.values.firstWhere(
        (s) => s.name == stateName,
        orElse: () => DownloadState.queued,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      totalBytes: json['totalBytes'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      localPath: json['localPath'] as String? ?? '',
      addedAt: json['addedAt'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String? ?? '',
    );
  }

  final String id;
  final String taskId;
  final String title;
  final String episodeUrl;
  final String playUrl;
  final Map<String, String> playHeaders;
  final DownloadState state;
  final double progress;
  final int totalBytes;
  final int downloadedBytes;
  final String localPath;
  final int addedAt;
  final String errorMessage;

  DownloadEpisode copyWith({
    DownloadState? state,
    double? progress,
    int? totalBytes,
    int? downloadedBytes,
    String? localPath,
    String? errorMessage,
  }) {
    return DownloadEpisode(
      id: id,
      taskId: taskId,
      title: title,
      episodeUrl: episodeUrl,
      playUrl: playUrl,
      playHeaders: playHeaders,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      localPath: localPath ?? this.localPath,
      addedAt: addedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'title': title,
      'episodeUrl': episodeUrl,
      'playUrl': playUrl,
      'playHeaders': playHeaders,
      'state': state.name,
      'progress': progress,
      'totalBytes': totalBytes,
      'downloadedBytes': downloadedBytes,
      'localPath': localPath,
      'addedAt': addedAt,
      'errorMessage': errorMessage,
    };
  }
}
