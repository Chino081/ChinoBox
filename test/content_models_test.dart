import 'package:chinobox/src/features/content/domain/content_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HistoryEntry keeps playback headers through json', () {
    const entry = HistoryEntry(
      id: 'libvio:episode',
      sourceId: 'libvio',
      title: 'Title',
      detailUrl: 'https://example.com/detail',
      episodeTitle: 'E01',
      episodeUrl: 'https://example.com/episode',
      playUrl: 'https://video.example.com/a.mp4',
      playHeaders: {
        'Referer': 'https://www.libvio.run/',
        'User-Agent': 'Mozilla/5.0',
      },
      position: 1200,
      duration: 5000,
    );

    final decoded = HistoryEntry.fromJson(entry.toJson());

    expect(decoded.playHeaders['Referer'], 'https://www.libvio.run/');
    expect(decoded.position, 1200);
    expect(decoded.duration, 5000);
  });
}
