import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../content/data/content_repository.dart';
import '../content/domain/content_models.dart';
import '../source/domain/source_catalog.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    required this.sourceId,
    required this.title,
    required this.poster,
    required this.detailUrl,
    required this.episodeTitle,
    required this.episodeUrl,
    required this.playUrl,
    required this.playHeaders,
    super.key,
  });

  factory PlayerPage.fromQuery(Map<String, String> params) {
    return PlayerPage(
      sourceId: params['source'] ?? '',
      title: params['title'] ?? '',
      poster: params['poster'] ?? '',
      detailUrl: params['detailUrl'] ?? '',
      episodeTitle: params['episodeTitle'] ?? '',
      episodeUrl: params['episodeUrl'] ?? '',
      playUrl: params['playUrl'] ?? '',
      playHeaders: _decodeHeaders(params['playHeaders'] ?? ''),
    );
  }

  final String sourceId;
  final String title;
  final String poster;
  final String detailUrl;
  final String episodeTitle;
  final String episodeUrl;
  final String playUrl;
  final Map<String, String> playHeaders;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  var _position = Duration.zero;
  var _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _positionSub = _player.stream.position.listen((value) => _position = value);
    _durationSub = _player.stream.duration.listen((value) => _duration = value);
    unawaited(_player.open(Media(
      widget.playUrl,
      httpHeaders: widget.playHeaders.isEmpty ? null : widget.playHeaders,
    )));
    unawaited(_saveHistory());
  }

  @override
  void dispose() {
    unawaited(_saveHistory());
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _saveHistory() async {
    final id = '${widget.sourceId}:${widget.episodeUrl}';
    await ref.read(contentRepositoryProvider).saveHistory(
          HistoryEntry(
            id: id,
            sourceId: widget.sourceId,
            title: widget.title,
            detailUrl: widget.detailUrl,
            episodeTitle: widget.episodeTitle,
            episodeUrl: widget.episodeUrl,
            playUrl: widget.playUrl,
            playHeaders: widget.playHeaders,
            poster: widget.poster,
            position: _position.inMilliseconds,
            duration: _duration.inMilliseconds,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final source = sourceById(widget.sourceId);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.title} ${widget.episodeTitle}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text(source.name)),
          ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(controller: _controller),
        ),
      ),
    );
  }
}

Map<String, String> _decodeHeaders(String value) {
  if (value.isEmpty) return const {};
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(value)))
        as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  } catch (_) {
    return const {};
  }
}
