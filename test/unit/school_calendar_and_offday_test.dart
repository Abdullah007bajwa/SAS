import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:school_attendance_portal/core/database/app_database.dart';
import 'package:school_attendance_portal/core/database/demo_seeder.dart';
import 'package:school_attendance_portal/core/hardware/k50_device_user_map.dart';
import 'package:school_attendance_portal/core/hardware/school_attendance_processor.dart';
import 'package:school_attendance_portal/core/hardware/zk_attendance_dedup.dart';
import 'package:school_attendance_portal/core/hardware/zk_backend_client.dart';
import 'package:school_attendance_portal/core/notifications/absence_cutoff_service.dart';
import 'package:school_attendance_portal/core/notifications/notification_provider.dart';
import 'package:school_attendance_portal/core/services/school_calendar_service.dart';
import '../test_helper.dart';

class MockNotificationProvider implements NotificationProvider {
  @override
  String get name => 'mock_provider';

  int smsSent = 0;
  int whatsappSent = 0;

  @override
  Future<NotificationSendResult> sendSms({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    smsSent++;
    return const NotificationSendResult(success: true, messageId: 'SMS_MOCK_123');
  }

  @override
  Future<NotificationSendResult> sendWhatsApp({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    whatsappSent++;
    return const NotificationSendResult(success: true, messageId: 'WA_MOCK_123');
  }
}

void main() {
  setupSqliteForTests();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DemoSeeder.seed(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SchoolCalendarService Tests', () {
    test('Correctly identifies Sunday as weekend by default', () {
      final sunday = DateTime(2026, 9, 27);
      final monday = DateTime(2026, 9, 28);

      expect(SchoolCalendarService.isWeekend(sunday), isTrue);
      expect(SchoolCalendarService.isWeekend(monday), isFalse);
      expect(SchoolCalendarService.isOffDay(sunday), isTrue);
      expect(SchoolCalendarService.isOffDay(monday), isFalse);
    });

    test('Parses custom weekly off-days like Sunday and Saturday', () {
      final saturday = DateTime(2026, 9, 26);
      final sunday = DateTime(2026, 9, 27);
      final monday = DateTime(2026, 9, 28);

      const customOffDays = 'Sunday, Saturday';

      expect(SchoolCalendarService.isWeekend(saturday, weeklyOffDays: customOffDays), isTrue);
      expect(SchoolCalendarService.isWeekend(sunday, weeklyOffDays: customOffDays), isTrue);
      expect(SchoolCalendarService.isWeekend(monday, weeklyOffDays: customOffDays), isFalse);
    });

    test('Identifies gazetted school holidays correctly', () {
      final holidayDate = DateTime(2026, 12, 25);
      final regularDate = DateTime(2026, 12, 24);

      const holidays = '2026-12-25, 2026-01-01';

      expect(SchoolCalendarService.isHoliday(holidayDate, holidaysStr: holidays), isTrue);
      expect(SchoolCalendarService.isHoliday(regularDate, holidaysStr: holidays), isFalse);
      expect(SchoolCalendarService.isOffDay(holidayDate, holidaysStr: holidays), isTrue);
    });

    test('Calculates school working days excluding Sundays', () {
      final start = DateTime(2026, 9, 21);
      final end = DateTime(2026, 9, 27);

      final workingDays = SchoolCalendarService.calculateWorkingDays(
        start: start,
        end: end,
        weeklyOffDays: 'Sunday',
      );
      final offDays = SchoolCalendarService.calculateOffDaysCount(
        start: start,
        end: end,
        weeklyOffDays: 'Sunday',
      );

      expect(workingDays, equals(6));
      expect(offDays, equals(1));
    });

    test('Calculates monthly working days excluding Sundays and holidays', () {
      final start = DateTime(2026, 9, 1);
      final end = DateTime(2026, 9, 30);

      final workingDays = SchoolCalendarService.calculateWorkingDays(
        start: start,
        end: end,
        weeklyOffDays: 'Sunday',
        holidaysStr: '2026-09-15',
      );

      // 30 - 4 Sundays - 1 holiday = 25 working days
      expect(workingDays, equals(25));
    });
  });

  group('AbsenceCutoffService Off-Day Awareness Tests', () {
    test('Skips absence evaluation and parent alerts on Sunday', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dedup = ZkAttendanceDedup(prefs);
      final userMap = K50DeviceUserMap(prefs);
      final processor = SchoolAttendanceProcessor(
        db: db,
        backendClient: ZkBackendClient(baseUrl: 'http://127.0.0.1:8787'),
        dedup: dedup,
        deviceUserMap: userMap,
      );
      final notificationProvider = MockNotificationProvider();
      final cutoffService = AbsenceCutoffService(
        db: db,
        attendanceProcessor: processor,
        notificationProvider: notificationProvider,
      );

      // 2026-09-27 is a Sunday
      final sunday = DateTime(2026, 9, 27, 8, 30);

      final result = await cutoffService.evaluateCutoffAndNotify(date: sunday);

      expect(result.isOffDay, isTrue);
      expect(result.absencesDetected, equals(0));
      expect(result.smsJobsCreated, equals(0));
      expect(result.whatsappJobsCreated, equals(0));

      final attendances = await db.attendanceDao.queryAttendances(date: '2026-09-27');
      expect(attendances.where((a) => a.status == 'absent'), isEmpty);
    });
  });

  group('Photo Path Persistence Tests', () {
    test('Persists photo path when inserting and updating student', () async {
      final studentId = await db.studentsDao.insertStudent(
        studentCode: 'STU-9901',
        name: 'Peter Parker',
        photoPath: '/home/photos/spidey.jpg',
      );

      var student = await db.studentsDao.getStudentById(studentId);
      expect(student, isNotNull);
      expect(student!.photoPath, equals('/home/photos/spidey.jpg'));

      await db.studentsDao.updateStudent(
        studentId,
        photoPath: 'avatar:scholar',
      );

      student = await db.studentsDao.getStudentById(studentId);
      expect(student, isNotNull);
      expect(student!.photoPath, equals('avatar:scholar'));
    });

    test('Persists photo path when inserting and updating staff', () async {
      final staffId = await db.staffDao.insertStaff(
        name: 'Minerva McGonagall',
        email: 'minerva@hogwarts.local',
        passwordHash: 'dummy_hash',
        photoPath: 'avatar:teacher_f',
      );

      var staff = await db.staffDao.getStaffById(staffId);
      expect(staff, isNotNull);
      expect(staff!.photoPath, equals('avatar:teacher_f'));

      await db.staffDao.updateStaff(
        staffId,
        photoPath: '/home/photos/mcgonagall.png',
      );

      staff = await db.staffDao.getStaffById(staffId);
      expect(staff, isNotNull);
      expect(staff!.photoPath, equals('/home/photos/mcgonagall.png'));
    });
  });
}

