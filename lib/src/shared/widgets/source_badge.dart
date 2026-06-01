import 'package:flutter/material.dart';

import '../../features/source/domain/media_source.dart';

class SourceBadge extends StatelessWidget {
  const SourceBadge({required this.source, super.key});

  final MediaSource source;

  @override
  Widget build(BuildContext context) {
    final color = switch (source.health) {
      SourceHealth.normal => Colors.green,
      SourceHealth.abnormal => Colors.orange,
      SourceHealth.noLongerUpdated => Colors.grey,
      SourceHealth.shutdown => Colors.red,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text('${source.kindLabel} · ${source.healthLabel}'),
    );
  }
}
