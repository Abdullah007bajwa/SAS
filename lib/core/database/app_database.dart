import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'daos/activity_dao.dart';
import 'daos/attendance_dao.dart';
import 'daos/classes_dao.dart';
import 'daos/enrollments_dao.dart';
import 'daos/notifications_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/staff_dao.dart';
import 'daos/students_dao.dart';
import 'daos/sections_dao.dart';
import 'daos/sync_dao.dart';
import 'tables/tables.dart';

const _uuid = Uuid();

@DriftDatabase(
  tables: [
    Users,
    Students,
    SchoolClasses,
    Sections,
    StudentEnrollments,
    SchoolAttendances,
    ParentNotificationJobs,
    NotificationDeliveryAttempts,
    SchoolSettings,
    ActivityLogs,
  ],
)
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  late final StudentsDao studentsDao = StudentsDao(this);
  late final ClassesDao classesDao = ClassesDao(this);
  late final SectionsDao sectionsDao = SectionsDao(this);
  late final StudentEnrollmentsDao enrollmentsDao = StudentEnrollmentsDao(this);
  late final StaffDao staffDao = StaffDao(this);
  late final AttendanceDao attendanceDao = AttendanceDao(this);
  late final NotificationsDao notificationsDao = NotificationsDao(this);
  late final SettingsDao settingsDao = SettingsDao(this);
  late final ActivityDao activityDao = ActivityDao(this);
  late final SyncDao syncDao = SyncDao(this);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated) {
            await seedInitialData();
          }
        },
      );

  @override
  List<TableInfo<Table, Object?>> get allTables => [];

  /// Seeds default admin, configuration settings, and starter grade/section.
  Future<void> seedInitialData() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Default admin account: admin@school.local / admin123
    final passwordHash = sha256.convert(utf8.encode('admin123')).toString();
    await customInsert(
      '''
      INSERT INTO users (
        sync_id, created_at, updated_at, is_synced,
        name, email, password_hash, role, phone,
        staff_category, employee_code, expected_start_time,
        grace_period_minutes, attendance_policy, status
      ) VALUES (?, ?, ?, 0, 'System Administrator', 'admin@school.local', ?, 'admin', '0000000000', 'administrator', 'ADM001', '08:00', 15, 'standard', 'active')
      ''',
      variables: [Variable(_uuid.v4()), Variable(now), Variable(now), Variable(passwordHash)],
    );

    // 2. Default School Settings
    final defaultSettings = {
      'school_name': 'School Attendance Portal',
      'student_cutoff_time': '08:30',
      'attendance_grace_period': '15',
      'student_id_range_start': '1001',
      'student_id_range_end': '7999',
      'staff_id_range_start': '8001',
      'staff_id_range_end': '8999',
      'k50_ip': '192.168.1.201',
      'k50_port': '4370',
      'k50_bridge_port': '8787',
      'sms_enabled': 'false',
      'whatsapp_enabled': 'false',
      'twilio_account_sid': '',
      'twilio_auth_token': '',
      'twilio_from_phone': '',
      'twilio_whatsapp_from': '',
      'absence_sms_template': 'Dear Parent, your child {student_name} is marked ABSENT today ({date}). Please contact school admin if this is an error.',
      'absence_whatsapp_template': 'Dear Parent, your child {student_name} is marked ABSENT today ({date}). Please contact the school office if you need assistance.',
    };

    for (final entry in defaultSettings.entries) {
      await settingsDao.setSetting(entry.key, entry.value);
    }

    // 3. Starter Class & Section
    final classId = await classesDao.insertClass(
      name: 'Grade 1',
      numericGrade: 1,
      description: 'First Grade Primary Class',
    );

    await sectionsDao.insertSection(
      classId: classId,
      name: 'Section A',
      roomNumber: '101',
      capacity: 35,
    );

    await activityDao.log(
      entityType: 'system',
      entityId: '1',
      action: 'init_database',
      details: 'Initial school portal database seeded with admin and default settings.',
    );
  }
}
