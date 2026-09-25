import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_attendance_portal/core/database/app_database.dart';
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
  });
}
