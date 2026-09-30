import 'package:drift/drift.dart';

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
import 'demo_seeder.dart';
import 'tables/tables.dart';

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
          await _createTables();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          try {
            await customStatement('PRAGMA journal_mode = WAL;');
            await customStatement('PRAGMA synchronous = NORMAL;');
          } catch (_) {}
          await _createTables();
          try {
            await customStatement('ALTER TABLE students ADD COLUMN photo_path TEXT');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE users ADD COLUMN photo_path TEXT');
          } catch (_) {}
          final userCountRow = await customSelect('SELECT COUNT(*) AS c FROM users').getSingle();
          if (userCountRow.read<int>('c') == 0) {
            await seedInitialData();
          }
        },
      );

  @override
  List<TableInfo<Table, Object?>> get allTables => [];

  Future<void> _createTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff',
        phone TEXT NOT NULL DEFAULT '',
        staff_category TEXT NOT NULL DEFAULT 'teacher',
        employee_code TEXT UNIQUE,
        fingerprint_id TEXT,
        expected_start_time TEXT NOT NULL DEFAULT '08:00',
        grace_period_minutes INTEGER NOT NULL DEFAULT 15,
        attendance_policy TEXT NOT NULL DEFAULT 'standard',
        status TEXT NOT NULL DEFAULT 'active',
        session_epoch INTEGER NOT NULL DEFAULT 0,
        photo_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        student_code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        gender TEXT,
        dob INTEGER,
        parent_name TEXT NOT NULL DEFAULT '',
        parent_phone TEXT NOT NULL DEFAULT '',
        whatsapp_phone TEXT NOT NULL DEFAULT '',
        notification_opt_in INTEGER NOT NULL DEFAULT 1,
        enrollment_status TEXT NOT NULL DEFAULT 'enrolled',
        fingerprint_id TEXT,
        photo_path TEXT,
        created_by INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS school_classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        numeric_grade INTEGER,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        class_id INTEGER NOT NULL REFERENCES school_classes(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        room_number TEXT,
        capacity INTEGER NOT NULL DEFAULT 40,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS student_enrollments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
        class_id INTEGER NOT NULL REFERENCES school_classes(id) ON DELETE CASCADE,
        section_id INTEGER NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
        academic_year TEXT NOT NULL,
        roll_number TEXT,
        start_date INTEGER NOT NULL,
        end_date INTEGER,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS school_attendances (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        person_type TEXT NOT NULL,
        student_id INTEGER REFERENCES students(id) ON DELETE SET NULL,
        staff_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        check_in_time INTEGER,
        check_out_time INTEGER,
        status TEXT NOT NULL DEFAULT 'present',
        method TEXT NOT NULL DEFAULT 'fingerprint',
        notes TEXT,
        recorded_by INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS parent_notification_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        channel TEXT NOT NULL,
        recipient_phone TEXT NOT NULL,
        message TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        scheduled_at INTEGER NOT NULL,
        sent_at INTEGER,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS notification_delivery_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        job_id INTEGER NOT NULL REFERENCES parent_notification_jobs(id) ON DELETE CASCADE,
        attempt_number INTEGER NOT NULL DEFAULT 1,
        attempted_at INTEGER NOT NULL,
        provider TEXT NOT NULL DEFAULT 'twilio',
        provider_message_id TEXT,
        status TEXT NOT NULL,
        response_body TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS school_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        key TEXT UNIQUE NOT NULL,
        value TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        action TEXT NOT NULL,
        details TEXT,
        performed_by INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await customStatement('CREATE INDEX IF NOT EXISTS idx_attendances_date_person ON school_attendances(date, person_type);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_attendances_student ON school_attendances(student_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_attendances_staff ON school_attendances(staff_id);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_enrollments_student ON student_enrollments(student_id, status);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_enrollments_class_sec ON student_enrollments(class_id, section_id, status);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_notif_jobs_status ON parent_notification_jobs(status, date);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_users_code ON users(employee_code);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_students_code ON students(student_code);');
  }

  /// Seeds configuration settings and primary admin account.
  /// Set [demoData] to true only if sample students and attendances are explicitly requested.
  Future<void> seedInitialData({bool demoData = false}) async {
    if (demoData) {
      await DemoSeeder.seed(this);
    } else {
      await DemoSeeder.seedDefaultsOnly(this);
    }
  }
}
