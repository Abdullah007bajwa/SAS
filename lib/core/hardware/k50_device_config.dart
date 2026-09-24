import 'dart:convert';

class K50DeviceConfig {
  const K50DeviceConfig({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 4370,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String ip;
  final int port;
  final bool enabled;

  K50DeviceConfig copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    bool? enabled,
  }) {
    return K50DeviceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'enabled': enabled,
      };

  factory K50DeviceConfig.fromJson(Map<String, dynamic> json) {
    return K50DeviceConfig(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'K50',
      ip: json['ip'] as String,
      port: json['port'] as int? ?? 4370,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  static List<K50DeviceConfig> listFromJson(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => K50DeviceConfig.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static String listToJson(List<K50DeviceConfig> devices) {
    return jsonEncode(devices.map((d) => d.toJson()).toList());
  }
}
