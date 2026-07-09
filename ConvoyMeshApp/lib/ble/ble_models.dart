class BleDeviceData {
  final String id;
  final String name;
  final int rssi;
  final DateTime lastSeen;

  BleDeviceData({
    required this.id,
    required this.name,
    required this.rssi,
    required this.lastSeen,
  });

  BleDeviceData copyWith({
    String? id,
    String? name,
    int? rssi,
    DateTime? lastSeen,
  }) {
    return BleDeviceData(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
