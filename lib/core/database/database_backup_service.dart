import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/photo_storage_service.dart';
import 'app_database.dart';

class BackupItem {
  final String fileName;
  final String filePath;
  final int sizeBytes;
  final DateTime createdAt;
  final bool isAutomatic;
  final int photoCount;

  BackupItem({
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.createdAt,
    required this.isAutomatic,
    this.photoCount = 0,
  });

  bool get isZip => fileName.toLowerCase().endsWith('.zip');

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

  /// Creates a consistent, crash-resilient backup archive (.zip) containing:
  /// 1. The SQLite database file (school_attendance.sqlite)
  /// 2. All student and staff profile photos (photos/*)
  /// 3. Manifest metadata (backup_manifest.json)
  Future<BackupItem> createBackup(
    AppDatabase db, {
    String? tag,
    Directory? customBackupDir,
    Directory? customPhotosDir,
    File? customLiveDb,
  }) async {
    final backupDir = customBackupDir ?? await getBackupDirectory();
    final now = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final tagSuffix = tag != null && tag.isNotEmpty ? '_$tag' : '';
    final zipFileName = 'SchoolAttendance_Backup_$stamp$tagSuffix.zip';
    final backupZipFile = File(p.join(backupDir.path, zipFileName));

    // 1. Flush any pending WAL writes to main database file
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}

    // 2. Perform online vacuum backup if supported by SQLite engine
    final tempDbFile = File(p.join(backupDir.path, 'temp_snapshot_$stamp.sqlite'));
    bool vacuumSucceeded = false;
    try {
      final safePath = tempDbFile.path.replaceAll("'", "''");
      await db.customStatement("VACUUM INTO '$safePath';");
      vacuumSucceeded = await tempDbFile.exists() && await tempDbFile.length() > 0;
    } catch (e) {
      debugPrint('[BackupService] VACUUM INTO fallback to file copy: $e');
    }

    // Direct binary copy fallback if VACUUM INTO not supported
    if (!vacuumSucceeded) {
      final liveDb = customLiveDb ?? await getLiveDatabaseFile();
      if (await liveDb.exists()) {
        await liveDb.copy(tempDbFile.path);
      } else if (!await tempDbFile.exists()) {
        await tempDbFile.writeAsBytes([], flush: true);
      }
    }

    // 3. Assemble zip archive
    final archive = Archive();

    // 3a. Add SQLite DB
    int dbSize = 0;
    if (await tempDbFile.exists()) {
      final dbBytes = await tempDbFile.readAsBytes();
      dbSize = dbBytes.length;
      archive.addFile(ArchiveFile('school_attendance.sqlite', dbBytes.length, dbBytes));
    }

    // 3b. Add all photos from the managed photos folder
    int photoCount = 0;
    try {
      final photosDir = customPhotosDir ?? await PhotoStorageService.getPhotosDirectory();
      if (await photosDir.exists()) {
        final entities = await photosDir.list(recursive: false).toList();
        for (final entity in entities) {
          if (entity is File) {
            final pBytes = await entity.readAsBytes();
            final name = p.basename(entity.path);
            archive.addFile(ArchiveFile('photos/$name', pBytes.length, pBytes));
            photoCount++;
          }
        }
      }
    } catch (e) {
      debugPrint('[BackupService] Warning reading photos: $e');
    }

    // 3c. Add manifest metadata
    final manifestMap = {
      'version': 1,
      'createdAt': now.toIso8601String(),
      'tag': tag ?? 'manual',
      'databaseBytes': dbSize,
      'photoCount': photoCount,
      'appName': 'SchoolAttendanceApp',
    };
    final manifestBytes = utf8.encode(jsonEncode(manifestMap));
    archive.addFile(ArchiveFile('backup_manifest.json', manifestBytes.length, manifestBytes));

    // 4. Encode & write .zip archive
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Failed to compress backup into zip archive');
    }
    await backupZipFile.writeAsBytes(zipData, flush: true);

    // 5. Cleanup temporary snapshot file
    if (await tempDbFile.exists()) {
      try {
        await tempDbFile.delete();
      } catch (_) {}
    }

    final totalSize = await backupZipFile.length();

    // 6. Log the backup creation in activity logs
    try {
      await db.activityDao.log(
        entityType: 'database',
        entityId: 'backup',
        action: 'create_backup',
        details: 'Full backup created: $zipFileName ($totalSize bytes, $photoCount photos)',
      );
    } catch (_) {}

    // 7. Auto-prune older backups to prevent unbounded disk usage
    await _pruneOldBackups(backupDir: customBackupDir);

    return BackupItem(
      fileName: zipFileName,
      filePath: backupZipFile.path,
      sizeBytes: totalSize,
      createdAt: now,
      isAutomatic: tag == 'auto',
      photoCount: photoCount,
    );
  }

  /// Lists all existing backup files (.zip full backups and legacy .sqlite), newest first.
  Future<List<BackupItem>> listBackups({Directory? customBackupDir}) async {
    final backupDir = customBackupDir ?? await getBackupDirectory();
    if (!await backupDir.exists()) return [];

    final entities = await backupDir.list().toList();
    final items = <BackupItem>[];

    for (final entity in entities) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.zip') || lower.endsWith('.sqlite')) {
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
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Restores a chosen backup file into the active database and photos directory.
  /// Handles both full .zip archives (restoring DB and photos) and legacy .sqlite files.
  Future<bool> restoreBackup(
    AppDatabase db,
    File backupFile, {
    File? customLiveDb,
    Directory? customPhotosDir,
  }) async {
    if (!await backupFile.exists()) {
      throw Exception('Backup file does not exist at ${backupFile.path}.');
    }

    final liveDb = customLiveDb ?? await getLiveDatabaseFile();
    final photosDir = customPhotosDir ?? await PhotoStorageService.getPhotosDirectory();

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

    final lower = backupFile.path.toLowerCase();
    int restoredPhotos = 0;

    if (lower.endsWith('.zip')) {
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (!file.isFile) continue;
        final data = file.content as List<int>;

        if (file.name == 'school_attendance.sqlite') {
          await File(liveDb.path).writeAsBytes(data, flush: true);
        } else if (file.name.startsWith('photos/')) {
          final photoName = file.name.substring('photos/'.length).trim();
          if (photoName.isNotEmpty && !photoName.contains('..')) {
            if (!await photosDir.exists()) {
              await photosDir.create(recursive: true);
            }
            final targetPhoto = File(p.join(photosDir.path, photoName));
            await targetPhoto.writeAsBytes(data, flush: true);
            restoredPhotos++;
          }
        }
      }
    } else if (lower.endsWith('.sqlite')) {
      // Direct binary copy for legacy .sqlite backups
      await backupFile.copy(liveDb.path);
    } else {
      throw Exception('Unsupported backup format. Expected .zip or .sqlite');
    }

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
        details: 'System restored from ${backupFile.path} (database + $restoredPhotos photos)',
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

  Future<void> _pruneOldBackups({Directory? backupDir}) async {
    try {
      final backups = await listBackups(customBackupDir: backupDir);
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
