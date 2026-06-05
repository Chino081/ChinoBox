import 'package:flutter/material.dart';

class LockButton extends StatelessWidget {
  const LockButton({
    required this.alignment,
    required this.locked,
    required this.onToggle,
    super.key,
  });

  final Alignment alignment;
  final bool locked;
  final VoidCallback onToggle;

  static List<Widget> buildPair({
    required bool locked,
    required VoidCallback onToggle,
  }) {
    return [
      LockButton(
        alignment: Alignment.centerLeft,
        locked: locked,
        onToggle: onToggle,
      ),
      LockButton(
        alignment: Alignment.centerRight,
        locked: locked,
        onToggle: onToggle,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SafeArea(
        left: alignment == Alignment.centerLeft,
        right: alignment == Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: IconButton(
            tooltip: locked ? '解锁按钮' : '锁定按钮',
            onPressed: onToggle,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0x33000000),
            ),
            icon:
                Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded),
          ),
        ),
      ),
    );
  }
}
