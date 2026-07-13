enum DeviceStatus { online, offline, busy }

DeviceStatus _parseStatus(String s) => switch (s) {
      'online' => DeviceStatus.online,
      'busy' => DeviceStatus.busy,
      _ => DeviceStatus.offline,
    };

class Device {
  const Device({
    required this.id,
    required this.hostname,
    required this.status,
    this.directoryId,
    this.osType,
    this.osVersion,
  });

  final String id;
  final String hostname;
  final DeviceStatus status;
  final String? directoryId;
  final String? osType;
  final String? osVersion;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        hostname: json['hostname'] as String? ?? json['id'] as String,
        status: _parseStatus(json['status'] as String? ?? 'offline'),
        directoryId: json['directory_id'] as String?,
        osType: json['os_type'] as String?,
        osVersion: json['os_version'] as String?,
      );
}
