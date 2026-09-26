import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class AttendanceRecordView {
  final int id;
  final String syncId;
  final String personType; // 'student' or 'staff'
  final int? studentId;
  final int? staffId;
  final String personName;
  final String personCode;
  final String? className;
  final String? sectionName;
  final String? staffCategory;
  final String date;
  final int? checkInTime;
  final int? checkOutTime;
  final String status; // 'present', 'late', 'half_day', 'absent'
  final String method; // 'fingerprint', 'code', 'manual'
  final String? notes;

  AttendanceRecordView({
    required this.id,
    required this.syncId,
    required this.personType,
    this.studentId,
    this.staffId,
    required this.personName,
    required this.personCode,
    this.className,
    this.sectionName,
    this.staffCategory,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
    required this.method,
    this.notes,
  });

  factory AttendanceRecordView.fromRow(QueryRow row) {
    return AttendanceRecordView(
      id: row.read<int>('id'),
      syncId: row.read<String>('sync_id'),
      personType: row.read<String>('person_type'),
      studentId: row.readNullable<int>('student_id'),
      staffId: row.readNullable<int>('staff_id'),
      personName: row.read<String>('person_name'),
      personCode: row.read<String>('person_code'),
      className: row.readNullable<String>('class_name'),
      sectionName: row.readNullable<String>('section_name'),
      staffCategory: row.readNullable<String>('staff_category'),
      date: row.read<String>('date'),
      checkInTime: row.readNullable<int>('check_in_time'),
      checkOutTime: row.readNullable<int>('check_out_time'),
      status: row.read<String>('status'),
      method: row.read<String>('method'),
      notes: row.readNullable<String>('notes'),
    );
  }
}

class AttendanceDao extends DatabaseAccessor<AppDatabase> {
  AttendanceDao(super.db);

  String todayDateString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<QueryRow?> getStudentAttendanceToday(int studentId, String date) async {
    final rows = await customSelect(
      '''
      SELECT * FROM school_attendances 
      WHERE person_type = 'student' AND student_id = ? AND date = ? 
      LIMIT 1
      ''',
      variables: [Variable(studentId), Variable(date)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> getStaffAttendanceToday(int staffId, String date) async {
    final rows = await customSelect(
      '''
      SELECT * FROM school_attendances 
      WHERE person_type = 'staff' AND staff_id = ? AND date = ? 
      LIMIT 1
      ''',
      variables: [Variable(staffId), Variable(date)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> recordStudentCheckIn({
    required int studentId,
    required DateTime timestamp,
    String method = 'fingerprint',
    String status = 'present',
    String? notes,
    int recordedBy = 0,
  }) async {
    final dateStr = '${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final existing = await getStudentAttendanceToday(studentId, dateStr);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (existing != null) {
      final existingCheckIn = existing.readNullable<int>('check_in_time');
      final attendanceId = existing.read<int>('id');

      if (existingCheckIn == null || (status == 'absent' && existing.read<String>('status') == 'late')) {
        // Previously marked absent, or correcting a scan that occurred past closing time
        await customUpdate(
          '''
          UPDATE school_attendances
          SET check_in_time = COALESCE(check_in_time, ?), status = ?, method = ?, notes = ?, updated_at = ?, is_synced = 0
          WHERE id = ?
          ''',
          variables: [
            Variable(timestamp.millisecondsSinceEpoch),
            Variable(status),
            Variable(method),
            Variable(notes),
            Variable(now),
            Variable(attendanceId),
          ],
        );
        return attendanceId;
      }

      // If already checked in and has no check-out, record check-out if scan is later
      final existingCheckOut = existing.readNullable<int>('check_out_time');
      final scanMs = timestamp.millisecondsSinceEpoch;
      if (existingCheckOut == null && scanMs > existingCheckIn) {
        // Debounce: check-out only if at least 2 minutes have passed since check-in
        if (scanMs - existingCheckIn > 2 * 60 * 1000) {
          await customUpdate(
            '''
            UPDATE school_attendances
            SET check_out_time = ?, updated_at = ?, is_synced = 0
            WHERE id = ?
            ''',
            variables: [
              Variable(scanMs),
              Variable(now),
              Variable(attendanceId),
            ],
          );
        }
      }

      return attendanceId;
    }

    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO school_attendances (
        sync_id, created_at, updated_at, is_synced,
        person_type, student_id, staff_id, date,
        check_in_time, check_out_time, status, method,
        notes, recorded_by
      ) VALUES (?, ?, ?, 0, 'student', ?, NULL, ?, ?, NULL, ?, ?, ?, ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(studentId),
        Variable(dateStr),
        Variable(timestamp.millisecondsSinceEpoch),
        Variable(status),
        Variable(method),
        Variable(notes),
        Variable(recordedBy),
      ],
    );
  }

  Future<int> recordStaffPunch({
    required int staffId,
    required DateTime timestamp,
    String method = 'fingerprint',
    String status = 'present',
    int recordedBy = 0,
  }) async {
    final dateStr = '${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final existing = await getStaffAttendanceToday(staffId, dateStr);

    final now = DateTime.now().millisecondsSinceEpoch;

    if (existing == null) {
      // First scan: Check-in
      final syncId = _uuid.v4();
      return customInsert(
        '''
        INSERT INTO school_attendances (
          sync_id, created_at, updated_at, is_synced,
          person_type, student_id, staff_id, date,
          check_in_time, check_out_time, status, method,
          recorded_by
        ) VALUES (?, ?, ?, 0, 'staff', NULL, ?, ?, ?, NULL, ?, ?, ?)
        ''',
        variables: [
          Variable(syncId),
          Variable(now),
          Variable(now),
          Variable(staffId),
          Variable(dateStr),
          Variable(timestamp.millisecondsSinceEpoch),
          Variable(status),
          Variable(method),
          Variable(recordedBy),
        ],
      );
    } else {
      final existingCheckIn = existing.readNullable<int>('check_in_time');
      final attendanceId = existing.read<int>('id');

      if (existingCheckIn == null) {
        // Staff was previously marked absent; update to checked-in
        await customUpdate(
          '''
          UPDATE school_attendances
          SET check_in_time = ?, status = ?, method = ?, updated_at = ?, is_synced = 0
          WHERE id = ?
          ''',
          variables: [
            Variable(timestamp.millisecondsSinceEpoch),
            Variable(status),
            Variable(method),
            Variable(now),
            Variable(attendanceId),
          ],
        );
        return attendanceId;
      }

      // Second scan: Check-out
      final existingCheckOut = existing.readNullable<int>('check_out_time');
      final scanMs = timestamp.millisecondsSinceEpoch;
      if (existingCheckOut == null && scanMs > existingCheckIn) {
        if (scanMs - existingCheckIn > 2 * 60 * 1000) {
          await customUpdate(
            '''
            UPDATE school_attendances
            SET check_out_time = ?, updated_at = ?, is_synced = 0
            WHERE id = ?
            ''',
            variables: [
              Variable(scanMs),
              Variable(now),
              Variable(attendanceId),
            ],
          );
        }
      }
      return attendanceId;
    }
  }

  Future<int> insertOrUpdateAttendance({
    required String personType,
    int? studentId,
    int? staffId,
    required String date,
    int? checkInTime,
    int? checkOutTime,
    String status = 'present',
    String method = 'fingerprint',
    String? notes,
    int recordedBy = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    final existing = personType == 'student'
        ? (studentId != null ? await getStudentAttendanceToday(studentId, date) : null)
        : (staffId != null ? await getStaffAttendanceToday(staffId, date) : null);

    if (existing != null) {
      final id = existing.read<int>('id');
      await customUpdate(
        '''
        UPDATE school_attendances
        SET check_in_time = COALESCE(?, check_in_time),
            check_out_time = COALESCE(?, check_out_time),
            status = ?,
            method = ?,
            notes = COALESCE(?, notes),
            updated_at = ?,
            is_synced = 0
        WHERE id = ?
        ''',
        variables: [
          Variable(checkInTime),
          Variable(checkOutTime),
          Variable(status),
          Variable(method),
          Variable(notes),
          Variable(now),
          Variable(id),
        ],
      );
      return id;
    } else {
      return customInsert(
        '''
        INSERT INTO school_attendances (
          sync_id, created_at, updated_at, is_synced,
          person_type, student_id, staff_id, date,
          check_in_time, check_out_time, status, method,
          notes, recorded_by
        ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable(syncId),
          Variable(now),
          Variable(now),
          Variable(personType),
          Variable(studentId),
          Variable(staffId),
          Variable(date),
          Variable(checkInTime),
          Variable(checkOutTime),
          Variable(status),
          Variable(method),
          Variable(notes),
          Variable(recordedBy),
        ],
      );
    }
  }

  Future<List<AttendanceRecordView>> queryAttendances({
    required String date,
    String? personType, // 'all', 'student', 'staff'
    int? classId,
    int? sectionId,
    String? status,
  }) async {
    final conditions = <String>['a.date = ?'];
    final variables = <Variable>[Variable(date)];

    if (personType != null && personType != 'all') {
      conditions.add('a.person_type = ?');
      variables.add(Variable(personType));
    }

    if (status != null && status != 'all') {
      conditions.add('a.status = ?');
      variables.add(Variable(status));
    }

    if (classId != null) {
      conditions.add('e.class_id = ?');
      variables.add(Variable(classId));
    }

    if (sectionId != null) {
      conditions.add('e.section_id = ?');
      variables.add(Variable(sectionId));
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final sql = '''
      SELECT a.*,
             CASE 
               WHEN a.person_type = 'student' THEN s.name 
               ELSE u.name 
             END AS person_name,
             CASE 
               WHEN a.person_type = 'student' THEN s.student_code 
               ELSE COALESCE(u.employee_code, 'EMP-' || u.id) 
             END AS person_code,
             c.name AS class_name,
             sec.name AS section_name,
             u.staff_category
      FROM school_attendances a
      LEFT JOIN students s ON a.student_id = s.id
      LEFT JOIN student_enrollments e ON s.id = e.student_id AND e.status = 'active'
      LEFT JOIN school_classes c ON e.class_id = c.id
      LEFT JOIN sections sec ON e.section_id = sec.id
      LEFT JOIN users u ON a.staff_id = u.id
      $whereClause
      ORDER BY a.check_in_time DESC
    ''';

    final rows = await customSelect(sql, variables: variables).get();
    return rows.map(AttendanceRecordView.fromRow).toList();
  }

  Future<int> countPresentToday(String personType, String date) async {
    final rows = await customSelect(
      '''
      SELECT COUNT(*) AS c 
      FROM school_attendances 
      WHERE person_type = ? AND date = ? AND status IN ('present', 'late')
      ''',
      variables: [Variable(personType), Variable(date)],
    ).get();
    return rows.first.read<int>('c');
  }

  Future<int> countLateToday(String personType, String date) async {
    final rows = await customSelect(
      '''
      SELECT COUNT(*) AS c 
      FROM school_attendances 
      WHERE person_type = ? AND date = ? AND status = 'late'
      ''',
      variables: [Variable(personType), Variable(date)],
    ).get();
    return rows.first.read<int>('c');
  }

  Future<int> countAbsentToday(String personType, String date) async {
    final rows = await customSelect(
      '''
      SELECT COUNT(*) AS c 
      FROM school_attendances 
      WHERE person_type = ? AND date = ? AND status = 'absent'
      ''',
      variables: [Variable(personType), Variable(date)],
    ).get();
    return rows.first.read<int>('c');
  }

  Future<List<AttendanceRecordView>> getRecentPunchStream({int limit = 20}) async {
    const sql = '''
      SELECT a.*,
             CASE 
               WHEN a.person_type = 'student' THEN s.name 
               ELSE u.name 
             END AS person_name,
             CASE 
               WHEN a.person_type = 'student' THEN s.student_code 
               ELSE COALESCE(u.employee_code, 'EMP-' || u.id) 
             END AS person_code,
             c.name AS class_name,
             sec.name AS section_name,
             u.staff_category
      FROM school_attendances a
      LEFT JOIN students s ON a.student_id = s.id
      LEFT JOIN student_enrollments e ON s.id = e.student_id AND e.status = 'active'
      LEFT JOIN school_classes c ON e.class_id = c.id
      LEFT JOIN sections sec ON e.section_id = sec.id
      LEFT JOIN users u ON a.staff_id = u.id
      WHERE a.check_in_time IS NOT NULL
      ORDER BY a.check_in_time DESC
      LIMIT ?
    ''';

    final rows = await customSelect(sql, variables: [Variable(limit)]).get();
    return rows.map(AttendanceRecordView.fromRow).toList();
  }

  Future<List<AttendanceRecordView>> getAttendanceHistoryForPerson({
    required String personType,
    int? studentId,
    int? staffId,
    int limit = 100,
  }) async {
    final condition = personType == 'student'
        ? "a.person_type = 'student' AND a.student_id = ?"
        : "a.person_type = 'staff' AND a.staff_id = ?";
    final targetId = personType == 'student' ? studentId : staffId;

    final sql = '''
      SELECT a.*,
             CASE 
               WHEN a.person_type = 'student' THEN s.name 
               ELSE u.name 
             END AS person_name,
             CASE 
               WHEN a.person_type = 'student' THEN s.student_code 
               ELSE COALESCE(u.employee_code, 'EMP-' || u.id) 
             END AS person_code,
             c.name AS class_name,
             sec.name AS section_name,
             u.staff_category
      FROM school_attendances a
      LEFT JOIN students s ON a.student_id = s.id
      LEFT JOIN student_enrollments e ON s.id = e.student_id AND e.status = 'active'
      LEFT JOIN school_classes c ON e.class_id = c.id
      LEFT JOIN sections sec ON e.section_id = sec.id
      LEFT JOIN users u ON a.staff_id = u.id
      WHERE $condition
      ORDER BY a.date DESC, a.check_in_time DESC
      LIMIT ?
    ''';

    final rows = await customSelect(sql, variables: [Variable(targetId), Variable(limit)]).get();
    return rows.map(AttendanceRecordView.fromRow).toList();
  }
}
