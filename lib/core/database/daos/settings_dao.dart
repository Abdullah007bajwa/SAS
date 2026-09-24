import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class SettingsDao extends DatabaseAccessor<AppDatabase> {
  SettingsDao(super.db);

  Future<String> getSetting(String key, {String defaultValue = ''}) async {
    final rows = await customSelect(
      'SELECT value FROM school_settings WHERE key = ? LIMIT 1',
      variables: [Variable(key)],
    ).get();
    if (rows.isEmpty) return defaultValue;
    return rows.first.read<String>('value');
  }

  Future<void> setSetting(String key, String value) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await customSelect(
      'SELECT id FROM school_settings WHERE key = ? LIMIT 1',
      variables: [Variable(key)],
    ).get();

    if (rows.isEmpty) {
      final syncId = _uuid.v4();
      await customInsert(
        '''
        INSERT INTO school_settings (sync_id, created_at, updated_at, is_synced, key, value)
        VALUES (?, ?, ?, 0, ?, ?)
        ''',
        variables: [Variable(syncId), Variable(now), Variable(now), Variable(key), Variable(value)],
      );
    } else {
      await customUpdate(
        'UPDATE school_settings SET value = ?, updated_at = ?, is_synced = 0 WHERE key = ?',
        variables: [Variable(value), Variable(now), Variable(key)],
      );
    }
  }

  Future<Map<String, String>> getAllSettings() async {
    final rows = await customSelect('SELECT key, value FROM school_settings').get();
    final map = <String, String>{};
    for (final row in rows) {
      map[row.read<String>('key')] = row.read<String>('value');
    }
    return map;
  }
}
