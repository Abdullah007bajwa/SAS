import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_provider.dart';
import '../hardware/hardware_providers.dart';
import 'sync_service.dart';

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final prefs = ref.watch(sharedPreferencesProvider);

  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } catch (_) {}

  final service = SyncService(
    db: db,
    prefs: prefs,
    supabaseClient: client,
    onStatusChanged: (status) {
      ref.read(syncStatusProvider.notifier).state = status;
    },
  );

  return service;
});
