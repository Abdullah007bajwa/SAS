import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages local storage of student and staff profile photos in a persistent,
/// app-managed directory so they are never lost if external files are moved/deleted.
class PhotoStorageService {
  PhotoStorageService._();

  /// Gets or creates the app-managed photos directory.
  static Future<Directory> getPhotosDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(
      p.join(docsDir.path, 'SchoolAttendance_Data', 'photos'),
    );
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  /// Copies an externally selected image into the managed photos directory.
  /// If the path is an avatar preset (e.g. "avatar:boy_1") or empty, returns as-is.
  static Future<String> persistPhoto(
    String sourcePath, {
    required String personType,
    required String code,
  }) async {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty || trimmed.startsWith('avatar:')) {
      return trimmed;
    }

    final sourceFile = File(trimmed);
    if (!await sourceFile.exists()) {
      return trimmed;
    }

    final photosDir = await getPhotosDirectory();

    // Already inside managed photos directory
    if (p.isWithin(photosDir.path, sourceFile.path)) {
      return sourceFile.path;
    }

    final ext = p.extension(sourceFile.path);
    final cleanExt = ext.isNotEmpty ? ext : '.jpg';
    final safeCode = code.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final fileName = '${personType}_${safeCode}_${DateTime.now().millisecondsSinceEpoch}$cleanExt';
    final targetFile = File(p.join(photosDir.path, fileName));

    await sourceFile.copy(targetFile.path);
    return targetFile.path;
  }

  /// Checks if a photo path points to an existing file or a valid avatar preset.
  static bool isValidPhoto(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    final trimmed = path.trim();
    if (trimmed.startsWith('avatar:')) return true;
    return File(trimmed).existsSync();
  }
}
