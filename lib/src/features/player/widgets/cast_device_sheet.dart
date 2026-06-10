import 'package:flutter/material.dart';

import '../models/cast_state.dart';

class CastDeviceSheet extends StatelessWidget {
  const CastDeviceSheet({
    required this.devices,
    required this.connectedDevice,
    super.key,
  });

  final List<CastDevice> devices;
  final CastDevice? connectedDevice;

  static Future<CastDevice?> show(
    BuildContext context, {
    required List<CastDevice> devices,
    CastDevice? connectedDevice,
  }) {
    return showModalBottomSheet<CastDevice>(
      context: context,
      backgroundColor: const Color(0xFF101010),
      showDragHandle: true,
      builder: (_) => CastDeviceSheet(
        devices: devices,
        connectedDevice: connectedDevice,
      ),
    );
  }

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
