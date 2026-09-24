import 'package:drift/drift.dart';
import '../app_database.dart';

class SyncDao extends DatabaseAccessor<AppDatabase> {
  SyncDao(super.db);

  /// Whitelist of tables synchronized with Supabase cloud.
  static const syncTables = [
    'users',
    'students',
    'school_classes',
    'sections',
    'student_enrollments',
    'school_attendances',
    'parent_notification_jobs',
    'notification_delivery_attempts',
    'school_settings',
    'activity_logs',
  ];

  Future<List<Map<String, dynamic>>> getUnsyncedRows(String table, {int limit = 50}) async {
    if (!syncTables.contains(table)) return [];
    final rows = await customSelect(
      'SELECT * FROM $table WHERE is_synced = 0 ORDER BY updated_at ASC LIMIT ?',
      variables: [Variable(limit)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<void> markRowsSynced(String table, List<String> syncIds) async {
    if (syncIds.isEmpty || !syncTables.contains(table)) return;
    final placeholders = List.filled(syncIds.length, '?').join(',');
    await customUpdate(
      'UPDATE $table SET is_synced = 1 WHERE sync_id IN ($placeholders)',
      variables: syncIds.map((id) => Variable(id)).toList(),
    );
  }

  Future<void> upsertRemoteRow(String table, Map<String, dynamic> data) async {
    if (!syncTables.contains(table)) return;

    final syncId = data['sync_id'] as String?;
    if (syncId == null) return;

    final existing = await customSelect(
      'SELECT id, updated_at, is_synced FROM $table WHERE sync_id = ? LIMIT 1',
      variables: [Variable(syncId)],
    ).get();

    final remoteUpdatedAt = data['updated_at'] is int
        ? data['updated_at'] as int
        : (data['updated_at'] != null
            ? DateTime.tryParse(data['updated_at'].toString())?.millisecondsSinceEpoch ?? 0
            : 0);

    // Filter valid columns for local SQLite
    final cols = <String>[];
    final values = <Variable>[];

    final filtered = Map<String, dynamic>.from(data)
      ..remove('id') // SQLite autoIncrements or preserves local id
      ..['is_synced'] = 1;

    if (existing.isNotEmpty) {
      final localUpdatedAt = existing.first.read<int>('updated_at');
      final isLocallyModified = existing.first.read<int>('is_synced') == 0;

      // Conflict resolution: if local has unsynced changes and local is newer, do not overwrite
      if (isLocallyModified && localUpdatedAt >= remoteUpdatedAt) {
        return;
      }

      final setClauses = <String>[];
      filtered.forEach((key, val) {
        if (key != 'sync_id') {
          setClauses.add('$key = ?');
          values.add(Variable(val));
        }
      });
      values.add(Variable(syncId));

      await customUpdate(
        'UPDATE $table SET ${setClauses.join(', ')} WHERE sync_id = ?',
        variables: values,
      );
    } else {
      final placeholders = <String>[];
      filtered.forEach((key, val) {
        cols.add(key);
        placeholders.add('?');
        values.add(Variable(val));
      });

      await customInsert(
        'INSERT INTO $table (${cols.join(', ')}) VALUES (${placeholders.join(', ')})',
        variables: values,
      );
    }
  }
}
