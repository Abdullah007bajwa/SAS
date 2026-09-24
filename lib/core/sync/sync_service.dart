import 'dart:async';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../database/daos/sync_dao.dart';

enum SyncStatus { idle, syncing, success, error }

/// Full bi-directional synchronization service between local Drift SQLite and Supabase Cloud.
class SyncService {
  SyncService({
    required AppDatabase db,
    required SharedPreferences prefs,
    SupabaseClient? supabaseClient,
    this.onStatusChanged,
  })  : _db = db,
        _prefs = prefs,
        _supabase = supabaseClient;

  final AppDatabase _db;
  final SharedPreferences _prefs;
  SupabaseClient? _supabase;
  final void Function(SyncStatus status)? onStatusChanged;

  static const _lastPullKey = 'sas_last_sync_pull_epoch';
  Timer? _periodicTimer;
  bool _isSyncing = false;

  void init(SupabaseClient? client) {
    _supabase = client;
    startPeriodicSync();
  }

  void startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> syncNow() async {
    if (_isSyncing) return;
    final client = _supabase;
    if (client == null) {
      developer.log('Supabase client not configured — skipping sync', name: 'SyncService');
      return;
    }

    _isSyncing = true;
    onStatusChanged?.call(SyncStatus.syncing);

    try {
      // 1. Push local changes to cloud
      for (final table in SyncDao.syncTables) {
        await _pushTable(client, table);
      }

      // 2. Pull remote changes to local SQLite
      final lastPull = _prefs.getInt(_lastPullKey) ?? 0;
      final currentEpoch = DateTime.now().millisecondsSinceEpoch;

      for (final table in SyncDao.syncTables) {
        await _pullTable(client, table, lastPull);
      }

      await _prefs.setInt(_lastPullKey, currentEpoch);
      onStatusChanged?.call(SyncStatus.success);
    } catch (e, st) {
      developer.log('Sync cycle encountered error', name: 'SyncService', error: e, stackTrace: st);
      onStatusChanged?.call(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pushTable(SupabaseClient client, String table) async {
    final unsynced = await _db.syncDao.getUnsyncedRows(table, limit: 100);
    if (unsynced.isEmpty) return;

    final records = <Map<String, dynamic>>[];
    final syncIds = <String>[];

    for (final row in unsynced) {
      final copy = Map<String, dynamic>.from(row)
        ..remove('id')
        ..remove('is_synced');
      records.add(copy);
      final syncId = row['sync_id'] as String?;
      if (syncId != null) syncIds.add(syncId);
    }

    try {
      await client.from(table).upsert(records, onConflict: 'sync_id');
      await _db.syncDao.markRowsSynced(table, syncIds);
      developer.log('Pushed ${records.length} rows to $table', name: 'SyncService');
    } catch (e, st) {
      developer.log('Failed pushing rows to $table', name: 'SyncService', error: e, stackTrace: st);
    }
  }

  Future<void> _pullTable(SupabaseClient client, String table, int lastPull) async {
    try {
      final response = await client
          .from(table)
          .select()
          .gt('updated_at', lastPull)
          .order('updated_at', ascending: true)
          .limit(200);

      final rows = response as List<dynamic>;
      for (final row in rows) {
        final data = Map<String, dynamic>.from(row as Map);
        await _db.syncDao.upsertRemoteRow(table, data);
      }
      if (rows.isNotEmpty) {
        developer.log('Pulled ${rows.length} rows from $table', name: 'SyncService');
      }
    } catch (e, st) {
      developer.log('Failed pulling rows from $table', name: 'SyncService', error: e, stackTrace: st);
    }
  }
}
