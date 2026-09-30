import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

      // Purge ONLY dummy data
      final deletedCount = await DemoSeeder.clearDummyData(db);
      expect(deletedCount, equals(16)); // Exact 16 demo students purged

      // Verify that user-created student Abdullah Bajwa STILL EXISTS!
      final remainingStudents = await db.studentsDao.getAllStudents();
      expect(remainingStudents.length, equals(1));
      expect(remainingStudents.first.studentCode, equals('STD-9901'));
      expect(remainingStudents.first.name, equals('Abdullah Bajwa'));

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
  });
}
