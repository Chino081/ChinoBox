import 'package:flutter/material.dart';

class ExternalOnlyView extends StatelessWidget {
  const ExternalOnlyView({
    required this.onReopenExternal,
    required this.onPlayInternal,
    super.key,
  });

  final VoidCallback onReopenExternal;
  final VoidCallback onPlayInternal;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new_rounded,
                  color: Colors.white70, size: 42),
              const SizedBox(height: 14),
              Text(
                '已交给外置播放器',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onReopenExternal,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('再次打开'),
                  ),
                  FilledButton.icon(
                    onPressed: onPlayInternal,
                    icon: const Icon(Icons.smart_display_rounded),
                    label: const Text('内置播放'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
