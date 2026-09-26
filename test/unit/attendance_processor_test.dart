import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:school_attendance_portal/core/database/app_database.dart';
import 'package:school_attendance_portal/core/database/demo_seeder.dart';
import 'package:school_attendance_portal/core/hardware/k50_device_user_map.dart';
import 'package:school_attendance_portal/core/hardware/school_attendance_processor.dart';
import 'package:school_attendance_portal/core/hardware/zk_attendance_dedup.dart';
import 'package:school_attendance_portal/core/hardware/zk_backend_client.dart';
import 'package:school_attendance_portal/core/hardware/zk_device_service.dart';
import '../test_helper.dart';

void main() {
  setupSqliteForTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;
  late ZkAttendanceDedup dedup;
  late K50DeviceUserMap userMap;
  late SchoolAttendanceProcessor processor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    await DemoSeeder.seed(db);

    dedup = ZkAttendanceDedup(prefs);
    userMap = K50DeviceUserMap(prefs);

    processor = SchoolAttendanceProcessor(
      db: db,
      backendClient: ZkBackendClient(baseUrl: 'http://127.0.0.1:8787'),
      dedup: dedup,
      deviceUserMap: userMap,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('SchoolAttendanceProcessor Tests', () {
    test('Student punch within range 1001-7999 records student attendance', () async {
      final now = DateTime.now();
      final log = LogEntry(
        userId: '1001',
        deviceUserId: '1001',
        timestamp: DateTime(now.year, now.month, now.day, 8, 5),
        verifyType: 1,
      );

      await processor.applyLogs([log]);

      final student = await db.studentsDao.getStudentByCode('STU-1001');
      expect(student, isNotNull);

      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final record = await db.attendanceDao.getStudentAttendanceToday(student!.id, dateStr);
      expect(record, isNotNull);
      expect(record!.read<String>('person_type'), 'student');
      expect(record.read<String>('status'), 'present');
    });

    test('Staff punch within range 8001-8999 records staff attendance', () async {
      final now = DateTime.now();
      final checkInLog = LogEntry(
        userId: '8001',
        deviceUserId: '8001',
        timestamp: DateTime(now.year, now.month, now.day, 7, 50),
        verifyType: 1,
      );

      await processor.applyLogs([checkInLog]);

      final staff = await db.staffDao.getStaffByEmployeeCode('TCH001');
      expect(staff, isNotNull);

      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final record = await db.attendanceDao.getStaffAttendanceToday(staff!.id, dateStr);
      expect(record, isNotNull);
      expect(record!.read<String>('person_type'), 'staff');
      expect(record.read<int?>('check_in_time'), isNotNull);

      // Second punch records check-out
      final checkOutLog = LogEntry(
        userId: '8001',
        deviceUserId: '8001',
        timestamp: DateTime(now.year, now.month, now.day, 16, 0),
        verifyType: 1,
      );

      await processor.applyLogs([checkOutLog]);

      final updatedRecord = await db.attendanceDao.getStaffAttendanceToday(staff.id, dateStr);
      expect(updatedRecord!.read<int?>('check_out_time'), isNotNull);
    });

    test('Deduplication prevents double insertion of identical punch', () async {
      final now = DateTime.now();
      final punchTime = DateTime(now.year, now.month, now.day, 8, 10);
      final log = LogEntry(
        userId: '1002',
        deviceUserId: '1002',
        timestamp: punchTime,
        verifyType: 1,
      );

      // Apply first time
      await processor.applyLogs([log]);

      // Apply duplicate punch
      await processor.applyLogs([log]);

      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final records = await db.attendanceDao.queryAttendances(date: dateStr);
      final occurrences = records.where((r) => r.personCode == 'STU-1002').toList();
      expect(occurrences.length, equals(1));
    });

    test('Punch updates student who was previously marked absent by auto-cutoff', () async {
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final studentId = await db.studentsDao.insertStudent(
        studentCode: 'STU-1099',
        name: 'Late Student',
        parentName: 'Parent',
        parentPhone: '+923000000000',
      );

      // Simulate cutoff marking student absent earlier in the day
      await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'student',
        studentId: studentId,
        date: dateStr,
        status: 'absent',
        method: 'system',
      );

      final initial = await db.attendanceDao.getStudentAttendanceToday(studentId, dateStr);
      expect(initial!.read<String>('status'), 'absent');
      expect(initial.read<int?>('check_in_time'), isNull);

      // Student arrives and scans thumb on K50
      final scanTime = DateTime(now.year, now.month, now.day, 9, 15);
      final log = LogEntry(
        userId: '1099',
        deviceUserId: '1099',
        timestamp: scanTime,
        verifyType: 1,
      );

      await processor.applyLogs([log]);

      final updated = await db.attendanceDao.getStudentAttendanceToday(studentId, dateStr);
      expect(updated, isNotNull);
      expect(updated!.read<String>('status'), 'late'); // Arrived after 08:30 cutoff
      expect(updated.read<int?>('check_in_time'), scanTime.millisecondsSinceEpoch);
      expect(updated.read<String>('method'), 'fingerprint');
    });

    test('Class-aware biometric ID resolves and records student punch', () async {
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      // Insert a student with class-aware code: Class 3, Section A, Roll 17 -> C3A-017
      final studentId = await db.studentsDao.insertStudent(
        studentCode: 'C3A-017',
        name: 'Abdullah Test',
        parentName: 'Parent',
        parentPhone: '+923001234567',
        fingerprintId: 'FP-3117',
      );
      await db.enrollmentsDao.enrollStudent(
        studentId: studentId,
        classId: 3,
        sectionId: 4, // Section 3-A
        academicYear: '2026-2027',
        rollNumber: '17',
      );

      // K50 logs biometric ID 3117
      final log = LogEntry(
        userId: '3117',
        deviceUserId: '3117',
        timestamp: DateTime(now.year, now.month, now.day, 8, 15),
        verifyType: 1,
      );

      await processor.applyLogs([log]);

      final record = await db.attendanceDao.getStudentAttendanceToday(studentId, dateStr);
      expect(record, isNotNull);
      expect(record!.read<String>('status'), 'present');
      expect(record.read<int?>('check_in_time'), isNotNull);
    });

    test('Student punch past school closing time records check_in_time but remains absent', () async {
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      // Closing time is configured as 14:00
      await db.settingsDao.setSetting('student_closing_time', '14:00');

      final studentId = await db.studentsDao.insertStudent(
        studentCode: 'C3A-018',
        name: 'Evening Punch Student',
        parentName: 'Parent',
        parentPhone: '+923009999999',
        fingerprintId: 'FP-3118',
      );

      // Student punches fingerprint at 19:30 (well past 14:00 closing)
      final eveningTime = DateTime(now.year, now.month, now.day, 19, 30);
      final log = LogEntry(
        userId: '3118',
        deviceUserId: '3118',
        timestamp: eveningTime,
        verifyType: 1,
      );

      await processor.applyLogs([log]);

      final record = await db.attendanceDao.getStudentAttendanceToday(studentId, dateStr);
      expect(record, isNotNull);
      // Biometric punch IS recorded
      expect(record!.read<int?>('check_in_time'), eveningTime.millisecondsSinceEpoch);
      expect(record.read<String>('method'), 'fingerprint');
      // Status remains absent
      expect(record.read<String>('status'), 'absent');
      expect(record.read<String?>('notes'), contains('closing'));

      // Also verify it shows in recent punches stream because check_in_time is populated
      final recent = await db.attendanceDao.getRecentPunchStream(limit: 5);
      expect(recent.any((r) => r.personCode == 'C3A-018'), isTrue);
    });
  });
}
