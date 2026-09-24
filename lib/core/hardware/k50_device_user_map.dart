import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Maps K50 device user IDs (e.g. 1001 or 8001) to application codes (e.g. STU-1001 or TCH-8001).
class K50DeviceUserMap {
  K50DeviceUserMap(this._prefs);

  static const _key = 'sas_k50_device_user_to_code_map';

  final SharedPreferences _prefs;

  Map<String, String> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k.toString().trim(), v.toString().trim()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> remember(String deviceUserId, String appCode) async {
    final device = deviceUserId.trim();
    final code = appCode.trim();
    if (device.isEmpty || code.isEmpty) return;

    final map = load();
    map[device] = code;
    await _prefs.setString(_key, jsonEncode(map));
  }

  String? appCodeForDeviceUser(String? deviceUserId) {
    if (deviceUserId == null || deviceUserId.trim().isEmpty) return null;
    return load()[deviceUserId.trim()];
  }
}
