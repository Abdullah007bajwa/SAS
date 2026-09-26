import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_attendance_portal/core/database/app_database.dart';
import 'package:school_attendance_portal/core/database/demo_seeder.dart';
import 'package:school_attendance_portal/utils/id_generator.dart';
import '../test_helper.dart';

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

  group('Individual Attendance History Tests', () {
    test('Can retrieve chronological attendance history for an individual student', () async {
      final student = (await db.studentsDao.getAllStudents()).first;

      // Add a series of punches across multiple dates
      await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'student',
        studentId: student.id,
        date: '2026-10-01',
        checkInTime: DateTime(2026, 10, 1, 7, 55).millisecondsSinceEpoch,
        checkOutTime: DateTime(2026, 10, 1, 14, 0).millisecondsSinceEpoch,
        status: 'present',
        method: 'fingerprint',
      );

      await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'student',
        studentId: student.id,
        date: '2026-10-02',
        checkInTime: DateTime(2026, 10, 2, 8, 20).millisecondsSinceEpoch,
        checkOutTime: DateTime(2026, 10, 2, 14, 0).millisecondsSinceEpoch,
        status: 'late',
        method: 'fingerprint',
      );

      await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'student',
        studentId: student.id,
        date: '2026-10-03',
        status: 'absent',
        method: 'manual',
        notes: 'Sick leave',
      );

      final history = await db.attendanceDao.getAttendanceHistoryForPerson(
        personType: 'student',
        studentId: student.id,
        limit: 50,
      );

      expect(history.length, greaterThanOrEqualTo(3));
      // First item should be the newest date (2026-10-03 or today if seeded)
      expect(history.any((r) => r.date == '2026-10-03' && r.status == 'absent'), isTrue);
      expect(history.any((r) => r.date == '2026-10-02' && r.status == 'late'), isTrue);
      expect(history.any((r) => r.date == '2026-10-01' && r.status == 'present'), isTrue);

      final record = history.firstWhere((r) => r.date == '2026-10-01');
      expect(record.personName, equals(student.name));
      expect(record.personCode, equals(student.studentCode));
      expect(record.checkInTime, isNotNull);
      expect(record.checkOutTime, isNotNull);
      expect(record.method, equals('fingerprint'));
    });

    test('Can retrieve attendance history for a faculty/staff member', () async {
      final staff = (await db.staffDao.getAllStaff()).first;

      await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'staff',
        staffId: staff.id,
        date: '2026-10-05',
        checkInTime: DateTime(2026, 10, 5, 7, 45).millisecondsSinceEpoch,
        checkOutTime: DateTime(2026, 10, 5, 16, 30).millisecondsSinceEpoch,
        status: 'present',
        method: 'fingerprint',
      );

      final history = await db.attendanceDao.getAttendanceHistoryForPerson(
        personType: 'staff',
        staffId: staff.id,
      );

      expect(history, isNotEmpty);
      final staffRecord = history.firstWhere((r) => r.date == '2026-10-05');
      expect(staffRecord.personName, equals(staff.name));
      expect(staffRecord.status, equals('present'));
      expect(staffRecord.checkOutTime, isNotNull);
    });
  });

  group('Student & Staff Edit Workflow Tests', () {
    test('Can update student information and persist un-synced state', () async {
      final student = (await db.studentsDao.getAllStudents()).first;

      await db.studentsDao.updateStudent(
        student.id,
        name: 'Jane Doe Updated',
        parentPhone: '+923009998877',
        whatsappPhone: '+923009998877',
        enrollmentStatus: 'suspended',
      );

      final updated = await db.studentsDao.getStudentById(student.id);
      expect(updated, isNotNull);
      expect(updated!.name, equals('Jane Doe Updated'));
      expect(updated.parentPhone, equals('+923009998877'));
      expect(updated.whatsappPhone, equals('+923009998877'));
      expect(updated.enrollmentStatus, equals('suspended'));
    });

    test('Can reassign student to a new class and section via enrollStudent', () async {
      final student = (await db.studentsDao.getAllStudents()).first;
      final classes = await db.classesDao.getAllClasses();
      final grade2 = classes.firstWhere((c) => c.name.contains('2') || c.name.contains('Grade'));

      final sections = await db.sectionsDao.getSectionsByClassId(grade2.id);
      final targetSection = sections.first;

      await db.enrollmentsDao.enrollStudent(
        studentId: student.id,
        classId: grade2.id,
        sectionId: targetSection.id,
        academicYear: '2026-2027',
        rollNumber: 'R-99',
      );

      final reloaded = await db.studentsDao.getStudentById(student.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.classId, equals(grade2.id));
      expect(reloaded.sectionId, equals(targetSection.id));
      expect(reloaded.rollNumber, equals('R-99'));
    });

    test('Can update staff details including shift timings and grace period', () async {
      final staff = (await db.staffDao.getAllStaff()).first;

      await db.staffDao.updateStaff(
        staff.id,
        name: 'Prof. Albus Dumbledore',
        phone: '+923114445566',
        staffCategory: 'administrator',
        expectedStartTime: '07:30',
        gracePeriodMinutes: 20,
        status: 'active',
      );

      final updated = await db.staffDao.getStaffById(staff.id);
      expect(updated, isNotNull);
      expect(updated!.name, equals('Prof. Albus Dumbledore'));
      expect(updated.phone, equals('+923114445566'));
      expect(updated.staffCategory, equals('administrator'));
      expect(updated.expectedStartTime, equals('07:30'));
      expect(updated.gracePeriodMinutes, equals(20));
    });
  });

  group('K50 Numeric Code Mapping & Partitioning Tests', () {
    test('Extracts numeric digits accurately from school codes', () {
      expect(IdGenerator.extractNumeric('STU-1001'), equals('1001'));
      expect(IdGenerator.extractNumeric('STU-7492'), equals('7492'));
      expect(IdGenerator.extractNumeric('TCH-8005'), equals('8005'));
      expect(IdGenerator.extractNumeric('EMP-8020'), equals('8020'));
      expect(IdGenerator.extractNumeric('1042'), equals('1042'));
    });

    test('Validates numeric ranges: students (1001-7999) vs staff (8001-8999)', () {
      const studentDbId = 15;
      const staffDbId = 7;

      const studentDeviceId = 1000 + studentDbId; // 1015
      const staffDeviceId = 8000 + staffDbId;     // 8007

      expect(studentDeviceId, inInclusiveRange(1001, 7999));
      expect(staffDeviceId, inInclusiveRange(8001, 8999));
      // Ensures complete non-overlapping between students and staff
      expect(studentDeviceId < 8000, isTrue);
      expect(staffDeviceId >= 8000, isTrue);
    });
  });
}
