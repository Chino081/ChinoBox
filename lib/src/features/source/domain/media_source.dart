enum SourceKind { movies, anime }

enum SourceHealth { normal, abnormal, noLongerUpdated, shutdown }

class MediaSource {
  const MediaSource({
    required this.id,
    required this.index,
    required this.name,
    required this.kind,
    required this.defaultDomain,
    required this.info,
    required this.health,
    this.releasePage = '',
    this.canSearch = true,
    this.rssPath = '',
    this.message = '',
    this.visible = true,
  });

  final String id;
  final int index;
  final String name;
  final SourceKind kind;
  final String defaultDomain;
  final String releasePage;
  final String info;
  final SourceHealth health;
  final bool canSearch;
  final String rssPath;
  final String message;
  final bool visible;

  bool get isAvailable => health != SourceHealth.shutdown;
  bool get isMaintained => health != SourceHealth.noLongerUpdated;
  bool get isSelectable => visible && isAvailable;
  bool get hasReleasePage => releasePage.isNotEmpty;
  bool get hasRss => rssPath.isNotEmpty;

  String get kindLabel => kind == SourceKind.movies ? '影视' : '动漫';

  String get healthLabel {
    return switch (health) {
      SourceHealth.normal => '正常',
      SourceHealth.abnormal => '部分异常',
      SourceHealth.noLongerUpdated => '不再维护',
      SourceHealth.shutdown => '站点关闭',
    };
  }
}
