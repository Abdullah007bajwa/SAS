import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';
import 'database_backup_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('AppDatabase must be overridden in ProviderScope');
});

final databaseBackupServiceProvider = Provider<DatabaseBackupService>((ref) {
  return DatabaseBackupService();
});
