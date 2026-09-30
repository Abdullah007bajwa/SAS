import 'dart:io';
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:school_attendance_portal/core/database/app_database.dart';
import 'package:school_attendance_portal/core/database/database_backup_service.dart';
import 'package:school_attendance_portal/core/database/demo_seeder.dart';
import '../test_helper.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Database & DemoSeeder Tests', () {
    test('Schema creation creates all 10 core tables without error', () async {
      // Trigger database open and tables creation
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ).get();

      final tableNames = tables.map((r) => r.read<String>('name')).toSet();

      expect(tableNames.contains('users'), isTrue);
      expect(tableNames.contains('students'), isTrue);
      expect(tableNames.contains('school_classes'), isTrue);
      expect(tableNames.contains('sections'), isTrue);
      expect(tableNames.contains('student_enrollments'), isTrue);
      expect(tableNames.contains('school_attendances'), isTrue);
      expect(tableNames.contains('parent_notification_jobs'), isTrue);
      expect(tableNames.contains('notification_delivery_attempts'), isTrue);
      expect(tableNames.contains('school_settings'), isTrue);
      expect(tableNames.contains('activity_logs'), isTrue);
    });

    test('DemoSeeder seeds students, staff, classes, and attendances', () async {
      await DemoSeeder.seed(db);

      // Verify Staff
      final staffCount = await db.staffDao.countActiveStaff();
      expect(staffCount, greaterThanOrEqualTo(8));

      // Verify Classes & Sections
      final classes = await db.classesDao.getAllClasses();
      expect(classes.length, greaterThanOrEqualTo(5));

      final sections = await db.sectionsDao.getAllSections();
      expect(sections.length, greaterThanOrEqualTo(6));

      // Verify Students
      final studentCount = await db.studentsDao.countActiveStudents();
      expect(studentCount, greaterThanOrEqualTo(16));

      // Verify Attendances
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final attendances = await db.attendanceDao.queryAttendances(date: dateStr);
      expect(attendances, isNotEmpty);

      // Verify Parent Notification Jobs
      final jobs = await db.notificationsDao.getNotificationHistory();
      expect(jobs, isNotEmpty);

      // Verify Settings
      final schoolName = await db.settingsDao.getSetting('school_name');
      expect(schoolName, contains('Springfield Academy'));
    });

    test('seedDefaultsOnly seeds only settings and single admin account', () async {
      await DemoSeeder.seedDefaultsOnly(db);

      // Verify no students, classes, or attendances exist
      expect(await db.studentsDao.countActiveStudents(), equals(0));
      expect(await db.classesDao.getAllClasses(), isEmpty);
      expect(await db.sectionsDao.getAllSections(), isEmpty);
      expect(await db.attendanceDao.queryAttendances(date: '2026-09-30'), isEmpty);

      // Verify only 1 admin staff exists
      final staff = await db.staffDao.getAllStaff();
      expect(staff.length, equals(1));
      expect(staff.first.role, equals('admin'));
      expect(staff.first.email, equals('admin@school.local'));

      // Verify essential settings exist
      expect(await db.settingsDao.getSetting('student_cutoff_time'), equals('08:30'));
      expect(await db.settingsDao.getSetting('k50_ip'), equals('192.168.18.78'));
    });

    test('clearDummyData purges ONLY dummy students while strictly preserving real user students', () async {
      // First populate with full demo data
      await DemoSeeder.seed(db);
      expect(await db.studentsDao.countActiveStudents(), greaterThan(0));

      // Add a real user-created student (e.g. Abdullah Bajwa)
      final userStudentId = await db.studentsDao.insertStudent(
        studentCode: 'STD-9901',
        name: 'Abdullah Bajwa',
        gender: 'male',
        dob: DateTime(2010, 5, 15).millisecondsSinceEpoch,
        parentName: 'Mr. Bajwa',
        parentPhone: '+923001234567',
        whatsappPhone: '+923001234567',
      );

      expect(userStudentId, greaterThan(0));

      // Add user-created class (Class 10) and section (Section B) without any students
      final class10Id = await db.classesDao.insertClass(
        name: 'Class 10',
        numericGrade: 10,
        description: 'Tenth Grade Secondary User Created',
      );
      final sectionBId = await db.sectionsDao.insertSection(
        classId: class10Id,
        name: 'Section B',
        roomNumber: '102-B',
        capacity: 40,
      );

      // Purge ONLY dummy data
      final deletedCount = await DemoSeeder.clearDummyData(db);
      expect(deletedCount, equals(16)); // Exact 16 demo students purged

      // Verify that user-created student Abdullah Bajwa STILL EXISTS!
      final remainingStudents = await db.studentsDao.getAllStudents();
      expect(remainingStudents.length, equals(1));
      expect(remainingStudents.first.studentCode, equals('STD-9901'));
      expect(remainingStudents.first.name, equals('Abdullah Bajwa'));

      // Verify user-created class 10 and section B are STILL PRESERVED!
      final allClasses = await db.classesDao.getAllClasses();
      expect(allClasses.any((c) => c.id == class10Id && c.name == 'Class 10'), isTrue);

      final allSections = await db.sectionsDao.getAllSections();
      expect(allSections.any((s) => s.id == sectionBId && s.name == 'Section B'), isTrue);

      // Verify admin account preserved
      final staff = await db.staffDao.getAllStaff();
      expect(staff.length, equals(1));
      expect(staff.first.role, equals('admin'));

      // Verify settings preserved
      expect(await db.settingsDao.getSetting('k50_ip'), isNotEmpty);
    });

    test('DatabaseBackupService checkIntegrity reports ok', () async {
      final backupService = DatabaseBackupService();
      final result = await backupService.checkIntegrity(db);
      expect(result, equals('ok'));
    });

    test('DatabaseBackupService creates full .zip archive with db and photos, and restores them', () async {
      final tempDir = await Directory.systemTemp.createTemp('sas_backup_test_');
      try {
        final testBackupDir = Directory(p.join(tempDir.path, 'backups'))..createSync();
        final testPhotosDir = Directory(p.join(tempDir.path, 'photos'))..createSync();
        final testLiveDb = File(p.join(tempDir.path, 'school_attendance.sqlite'))..writeAsBytesSync([1, 2, 3, 4, 5]);

        // Create sample photos
        final photo1 = File(p.join(testPhotosDir.path, 'student_1001.jpg'))..writeAsStringSync('fake-jpeg-data');
        final photo2 = File(p.join(testPhotosDir.path, 'staff_001.png'))..writeAsStringSync('fake-png-data');

        final backupService = DatabaseBackupService();
        final backupItem = await backupService.createBackup(
          db,
          tag: 'unit_test',
          customBackupDir: testBackupDir,
          customPhotosDir: testPhotosDir,
          customLiveDb: testLiveDb,
        );

        expect(backupItem.isZip, isTrue);
        expect(backupItem.photoCount, equals(2));
        expect(File(backupItem.filePath).existsSync(), isTrue);

        // Verify zip contents
        final zipBytes = await File(backupItem.filePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(zipBytes);
        final fileNames = archive.map((e) => e.name).toSet();
        expect(fileNames.contains('school_attendance.sqlite'), isTrue);
        expect(fileNames.contains('photos/student_1001.jpg'), isTrue);
        expect(fileNames.contains('photos/staff_001.png'), isTrue);
        expect(fileNames.contains('backup_manifest.json'), isTrue);

        // Delete photos and overwrite liveDb to test restore
        await photo1.delete();
        await photo2.delete();
        await testLiveDb.writeAsBytes([9, 9, 9]);

        expect(photo1.existsSync(), isFalse);
        expect(photo2.existsSync(), isFalse);

        // Restore
        final restoreDir = Directory(p.join(tempDir.path, 'restored_photos'));
        final restoredDbFile = File(p.join(tempDir.path, 'restored.sqlite'));

        await backupService.restoreBackup(
          db,
          File(backupItem.filePath),
          customLiveDb: restoredDbFile,
          customPhotosDir: restoreDir,
        );

        expect(restoredDbFile.existsSync(), isTrue);
        expect(File(p.join(restoreDir.path, 'student_1001.jpg')).existsSync(), isTrue);
        expect(File(p.join(restoreDir.path, 'staff_001.png')).existsSync(), isTrue);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
