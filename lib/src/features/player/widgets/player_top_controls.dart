import 'package:flutter/material.dart';

class PlayerTopControls extends StatelessWidget {
  const PlayerTopControls({
    required this.titleText,
    required this.isFullscreen,
    required this.supportsPiP,
    required this.onBack,
    required this.onExternal,
    required this.onPiP,
    required this.onFullscreen,
    super.key,
  });

  final String titleText;
  final bool isFullscreen;
  final bool supportsPiP;
  final VoidCallback onBack;
  final VoidCallback onExternal;
  final VoidCallback onPiP;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xAA000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 34),
            child: Row(
              children: [
                _OverlayIconButton(
                  tooltip: '返回',
                  icon: Icons.arrow_back_rounded,
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _OverlayIconButton(
                  tooltip: '外置播放器',
                  icon: Icons.open_in_new_rounded,
                  onPressed: onExternal,
                ),
                if (supportsPiP)
                  _OverlayIconButton(
                    tooltip: '画中画',
                    icon: Icons.picture_in_picture_alt_rounded,
                    onPressed: onPiP,
                  ),
                _OverlayIconButton(
                  tooltip: isFullscreen ? '退出全屏' : '全屏',
                  icon: isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  onPressed: onFullscreen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      color: Colors.white,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
