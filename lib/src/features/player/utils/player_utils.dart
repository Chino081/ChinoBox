import 'dart:convert';

const browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

const playbackRates = [0.75, 1.0, 1.25, 1.5, 2.0];

const controlAutoHideDelay = Duration(seconds: 5);

String formatRate(double rate) {
  return rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 2);
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

Map<String, String> decodeHeaders(String value) {
  if (value.isEmpty) return const {};
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(value)))
        as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  } catch (_) {
    return const {};
  }
}
