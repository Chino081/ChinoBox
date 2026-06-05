import 'package:flutter/material.dart';

import '../controllers/player_state_controller.dart';

class PlayerControlOverlay extends StatelessWidget {
  const PlayerControlOverlay({
    required this.state,
    required this.topControls,
    required this.centerControls,
    required this.bottomControls,
    required this.lockButtons,
    required this.lockButtonLeft,
    required this.lockButtonRight,
    super.key,
  });

  final PlayerStateController state;
  final Widget topControls;
  final Widget centerControls;
  final Widget bottomControls;
  final List<Widget> lockButtons;
  final Widget lockButtonLeft;
  final Widget lockButtonRight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: !state.controlsVisible,
            child: AnimatedOpacity(
              opacity: state.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: state.controlsLocked
                          ? Colors.transparent
                          : const Color(0x26000000),
                    ),
                  ),
                  if (!state.controlsLocked && state.isFullscreen) topControls,
                  if (state.controlsLocked) ...lockButtons,
                  if (!state.controlsLocked) ...[
                    lockButtonLeft,
                    lockButtonRight,
                    centerControls,
                    bottomControls,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
