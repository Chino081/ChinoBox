enum CastConnectionState { disconnected, connecting, connected }

class CastDevice {
  const CastDevice({
    required this.udn,
    required this.name,
    this.manufacturer = '',
  });

  final String udn;
  final String name;
  final String manufacturer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CastDevice && runtimeType == other.runtimeType && udn == other.udn;

  @override
  int get hashCode => udn.hashCode;
}

enum CastTransportState { idle, playing, paused, transitioning, stopped }
