import 'package:flutter/material.dart';

import '../utils/player_utils.dart';

class SpeedSheet extends StatelessWidget {
  const SpeedSheet({required this.currentRate, super.key});

  final double currentRate;

  static Future<double?> show(BuildContext context, double currentRate) {
    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      showDragHandle: true,
      builder: (_) => SpeedSheet(currentRate: currentRate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final rate in playbackRates)
            ListTile(
              leading: currentRate == rate
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : const SizedBox(width: 24),
              title: Text(
                '${formatRate(rate)}x',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.of(context).pop(rate),
            ),
        ],
      ),
    );
  }
}
