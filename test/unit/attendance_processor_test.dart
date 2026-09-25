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
  });
}
