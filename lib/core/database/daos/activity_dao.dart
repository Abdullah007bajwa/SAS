import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class ActivityLogEntry {
  final int id;
  final String syncId;
  final String entityType;
  final String? entityId;
  final String action;
  final String? details;
  final int performedBy;
  final int timestamp;

  ActivityLogEntry({
    required this.id,
    required this.syncId,
    required this.entityType,
    this.entityId,
    required this.action,
    this.details,
    required this.performedBy,
    required this.timestamp,
  });

  factory ActivityLogEntry.fromRow(QueryRow row) {
    return ActivityLogEntry(
      id: row.read<int>('id'),
      syncId: row.read<String>('sync_id'),
      entityType: row.read<String>('entity_type'),
      entityId: row.readNullable<String>('entity_id'),
      action: row.read<String>('action'),
      details: row.readNullable<String>('details'),
      performedBy: row.read<int>('performed_by'),
      timestamp: row.read<int>('timestamp'),
    );
  }
}

class ActivityDao extends DatabaseAccessor<AppDatabase> {
  ActivityDao(super.db);

  Future<int> log({
    required String entityType,
    String? entityId,
    required String action,
    String? details,
    int performedBy = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO activity_logs (
        sync_id, created_at, updated_at, is_synced,
        entity_type, entity_id, action, details,
        performed_by, timestamp
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(entityType),
        Variable(entityId),
        Variable(action),
        Variable(details),
        Variable(performedBy),
        Variable(now),
      ],
    );
  }

  Future<List<ActivityLogEntry>> getRecentLogs({int limit = 50}) async {
    final rows = await customSelect(
      'SELECT * FROM activity_logs ORDER BY timestamp DESC LIMIT ?',
      variables: [Variable(limit)],
    ).get();
    return rows.map(ActivityLogEntry.fromRow).toList();
  }
}
