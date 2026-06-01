import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/source_badge.dart';
import '../settings/settings_controller.dart';
import '../source/domain/media_source.dart';
import '../source/domain/source_catalog.dart';

Future<void> showSourceSwitchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const SourceSwitchSheet(),
  );
}

class SourceSwitchSheet extends ConsumerWidget {
  const SourceSwitchSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(settingsControllerProvider).sourceId;
    final sources = visibleSourceCatalog();
    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: sources.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final source = sources[index];
          return ListTile(
            enabled: source.isSelectable,
            leading: Icon(
              source.kind == SourceKind.movies
                  ? Icons.movie_outlined
                  : Icons.animation_outlined,
            ),
            title: Text(source.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                SourceBadge(source: source),
                if (source.message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(source.message),
                ],
              ],
            ),
            trailing:
                selected == source.id ? const Icon(Icons.check_rounded) : null,
            onTap: source.isSelectable
                ? () async {
                    await ref
                        .read(settingsControllerProvider.notifier)
                        .setSource(source.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                : null,
          );
        },
      ),
    );
  }
}
