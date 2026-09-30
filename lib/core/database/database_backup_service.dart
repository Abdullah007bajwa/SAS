import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

class BackupItem {
  final String fileName;
  final String filePath;
  final int sizeBytes;
  final DateTime createdAt;
  final bool isAutomatic;

  BackupItem({
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.createdAt,
    required this.isAutomatic,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedDate {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(createdAt);
  }
}

class DatabaseBackupService {
  static const int maxBackupsToKeep = 14;

  /// Returns the directory where backups are stored.
  Future<Directory> getBackupDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docsDir.path}${Platform.pathSeparator}SchoolAttendance_Backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Locates the live database file created by drift_flutter.
  Future<File> getLiveDatabaseFile() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return File('${docsDir.path}${Platform.pathSeparator}school_attendance.sqlite');
  }

  /// Creates a consistent, crash-resilient backup of the SQLite database.
  Future<BackupItem> createBackup(AppDatabase db, {String? tag}) async {
    final backupDir = await getBackupDirectory();
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final tagSuffix = tag != null && tag.isNotEmpty ? '_$tag' : '';
    final fileName = 'SchoolAttendance_Backup_$stamp$tagSuffix.sqlite';
    final backupFile = File('${backupDir.path}${Platform.pathSeparator}$fileName');

    // 1. Flush any pending WAL writes to main database file
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}

    // 2. Perform online vacuum backup if supported by SQLite engine
    bool vacuumSucceeded = false;
    try {
      final safePath = backupFile.path.replaceAll("'", "''");
      await db.customStatement("VACUUM INTO '$safePath';");
      vacuumSucceeded = await backupFile.exists() && await backupFile.length() > 0;
    } catch (e) {
      debugPrint('[BackupService] VACUUM INTO fallback to file copy: $e');
    }

    // 3. Fallback: direct binary copy of .sqlite file
    if (!vacuumSucceeded) {
      final liveDb = await getLiveDatabaseFile();
      if (await liveDb.exists()) {
        await liveDb.copy(backupFile.path);
      } else {
        throw Exception('Live database file not found at ${liveDb.path}');
      }
    }

    final size = await backupFile.length();

    // 4. Log the backup creation in activity logs
    try {
      await db.activityDao.log(
        entityType: 'database',
        entityId: 'backup',
        action: 'create_backup',
        details: 'Database backup created: $fileName ($size bytes)',
      );
    } catch (_) {}

    // 5. Auto-prune older backups to prevent unbounded disk usage
    await _pruneOldBackups();

    return BackupItem(
      fileName: fileName,
      filePath: backupFile.path,
      sizeBytes: size,
      createdAt: now,
      isAutomatic: tag == 'auto',
    );
  }

  /// Lists all existing backup files, newest first.
  Future<List<BackupItem>> listBackups() async {
    final backupDir = await getBackupDirectory();
    final entities = await backupDir.list().toList();
    final items = <BackupItem>[];

    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.sqlite')) {
        final stat = await entity.stat();
        final name = entity.uri.pathSegments.last;
        items.add(BackupItem(
          fileName: name,
          filePath: entity.path,
          sizeBytes: stat.size,
          createdAt: stat.modified,
          isAutomatic: name.contains('auto'),
        ));
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Restores a chosen backup file into the active database.
  Future<bool> restoreBackup(AppDatabase db, File backupFile) async {
    if (!await backupFile.exists()) {
      throw Exception('Backup file does not exist.');
    }

    final liveDb = await getLiveDatabaseFile();

    // Safety step: Create pre-restore emergency backup of live data before overwriting
    try {
      if (await liveDb.exists()) {
        await createBackup(db, tag: 'pre_restore');
      }
    } catch (_) {}

    // Close active WAL/SHM locks
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}

    // Copy backup over live database file
    await backupFile.copy(liveDb.path);

    // Remove old wal/shm if present so SQLite starts fresh with restored db
    final walFile = File('${liveDb.path}-wal');
    if (await walFile.exists()) {
      try { await walFile.delete(); } catch (_) {}
    }
    final shmFile = File('${liveDb.path}-shm');
    if (await shmFile.exists()) {
      try { await shmFile.delete(); } catch (_) {}
    }

    try {
      await db.activityDao.log(
        entityType: 'database',
        entityId: 'restore',
        action: 'restore_backup',
        details: 'Database restored from ${backupFile.path}',
      );
    } catch (_) {}

    return true;
  }

  /// Checks SQLite database integrity (PRAGMA integrity_check).
  Future<String> checkIntegrity(AppDatabase db) async {
    try {
      final rows = await db.customSelect('PRAGMA integrity_check;').get();
      if (rows.isNotEmpty) {
        final result = rows.first.data.values.first?.toString() ?? 'ok';
        return result;
      }
      return 'ok';
    } catch (e) {
      return 'Integrity check error: $e';
    }
  }

  /// Automatically creates a daily backup if none was created today.
  Future<void> autoDailyBackup(AppDatabase db) async {
    try {
      final backups = await listBackups();
      final today = DateTime.now();
      final hasBackupToday = backups.any((b) =>
          b.createdAt.year == today.year &&
          b.createdAt.month == today.month &&
          b.createdAt.day == today.day);

      if (!hasBackupToday) {
        await createBackup(db, tag: 'auto');
      }
    } catch (e) {
      debugPrint('[BackupService] Auto backup error: $e');
    }
  }

  /// Opens the local backup folder in Windows File Explorer or Linux file manager.
  Future<void> openBackupFolder() async {
    final backupDir = await getBackupDirectory();
    final path = backupDir.path;

    if (Platform.isWindows) {
      await Process.start('explorer.exe', [path], runInShell: true);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path]);
    }
  }

  Future<void> _pruneOldBackups() async {
    try {
      final backups = await listBackups();
      if (backups.length > maxBackupsToKeep) {
        for (int i = maxBackupsToKeep; i < backups.length; i++) {
          final file = File(backups[i].filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    } catch (_) {}
  }
}
