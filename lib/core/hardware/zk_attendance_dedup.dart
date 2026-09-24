import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists processed attendance keys so app restarts do not duplicate check-ins.
class ZkAttendanceDedup {
  ZkAttendanceDedup(this._prefs);

  static const _key = 'sas_processed_attendance_v1';
  static const _maxKeys = 5000;

  final SharedPreferences _prefs;

  Set<String> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Set<String> keys) async {
    final trimmed = keys.length <= _maxKeys
        ? keys.toList()
        : keys.toList().sublist(keys.length - _maxKeys);
    await _prefs.setString(_key, jsonEncode(trimmed));
  }

  bool contains(Set<String> keys, String key) => keys.contains(key);

  void add(Set<String> keys, String key) {
    keys.add(key);
    if (keys.length > _maxKeys) {
      final list = keys.toList()..removeAt(0);
      keys
        ..clear()
        ..addAll(list);
    }
  }
}
