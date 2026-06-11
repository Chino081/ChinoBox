import 'package:flutter/material.dart';

import '../controllers/player_state_controller.dart';
import '../models/cast_state.dart';

class CastDeviceSheet extends StatelessWidget {
  const CastDeviceSheet({
    required this.state,
    required this.onRefresh,
    super.key,
  });

  final PlayerStateController state;
  final VoidCallback onRefresh;

  static Future<CastDevice?> show(
    BuildContext context, {
    required PlayerStateController state,
    required VoidCallback onRefresh,
  }) {
    return showModalBottomSheet<CastDevice>(
      context: context,
      backgroundColor: const Color(0xFF101010),
      showDragHandle: true,
      builder: (_) => CastDeviceSheet(
        state: state,
        onRefresh: onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final devices = state.castDevices;
        final connectedDevice = state.connectedDevice;

        return _CastDeviceSheetBody(
          devices: devices,
          connectedDevice: connectedDevice,
          onRefresh: onRefresh,
        );
      },
    );
  }
}

class _CastDeviceSheetBody extends StatelessWidget {
  const _CastDeviceSheetBody({
    required this.devices,
    required this.connectedDevice,
    required this.onRefresh,
  });

  final List<CastDevice> devices;
  final CastDevice? connectedDevice;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '投屏设备',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                if (devices.isEmpty)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: '重新搜索',
                  icon: const Icon(Icons.refresh_rounded),
                  color: Colors.white70,
                  onPressed: onRefresh,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '正在搜索投屏设备...',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isConnected = device == connectedDevice;
                    return ListTile(
                      leading: Icon(
                        isConnected
                            ? Icons.cast_connected_rounded
                            : Icons.cast_outlined,
                        color: isConnected
                            ? const Color(0xFFFF4081)
                            : Colors.white70,
                      ),
                      title: Text(
                        device.name,
                        style: TextStyle(
                          color: isConnected
                              ? const Color(0xFFFF4081)
                              : Colors.white,
                          fontWeight:
                              isConnected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: device.manufacturer.isNotEmpty
                          ? Text(
                              device.manufacturer,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            )
                          : null,
                      trailing: isConnected
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFFFF4081))
                          : null,
                      onTap: () => Navigator.of(context).pop(device),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  },
                ),
              ),
            if (connectedDevice != null) ...[
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.cast_connected_rounded,
                    color: Colors.white70),
                title: const Text(
                  '断开投屏',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.of(context).pop(connectedDevice),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
