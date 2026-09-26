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
    await DemoSeeder.seed(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Manual Attendance & Filter Queries Tests', () {
    test('Can record manual attendance for a student', () async {
      const dateStr = '2026-10-15';
      final student = (await db.studentsDao.getAllStudents()).first;

      final id = await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'student',
        studentId: student.id,
        date: dateStr,
        checkInTime: DateTime(2026, 10, 15, 8, 45).millisecondsSinceEpoch,
        status: 'late',
        method: 'manual',
        notes: 'Parent notified traffic delay',
      );

      expect(id, greaterThan(0));

      final records = await db.attendanceDao.queryAttendances(
        date: dateStr,
        personType: 'student',
      );

      expect(records, isNotEmpty);
      final entry = records.firstWhere((r) => r.personCode == student.studentCode);
      expect(entry.status, equals('late'));
      expect(entry.method, equals('manual'));
      expect(entry.notes, equals('Parent notified traffic delay'));
    });

    test('Can query attendance with class and section filters', () async {
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final classes = await db.classesDao.getAllClasses();
      expect(classes, isNotEmpty);
      final grade1 = classes.firstWhere((c) => c.name == 'Grade 1');

      final records = await db.attendanceDao.queryAttendances(
        date: dateStr,
        classId: grade1.id,
      );

      expect(records, isNotEmpty);
      for (final r in records) {
        expect(r.className, equals('Grade 1'));
      }
    });

    test('Attendance counts for today match seeded expectations', () async {
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final presentStudents = await db.attendanceDao.countPresentToday('student', dateStr);
      final absentStudents = await db.attendanceDao.countAbsentToday('student', dateStr);
      final lateStudents = await db.attendanceDao.countLateToday('student', dateStr);

      expect(presentStudents, greaterThan(0));
      expect(absentStudents, greaterThan(0));
      expect(lateStudents, greaterThan(0));
    });
  });
}
