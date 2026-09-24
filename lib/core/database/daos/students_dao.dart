import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class StudentWithEnrollment {
  final int id;
  final String syncId;
  final String studentCode;
  final String name;
  final String? gender;
  final int? dob;
  final String parentName;
  final String parentPhone;
  final String whatsappPhone;
  final int notificationOptIn;
  final String enrollmentStatus;
  final String? fingerprintId;
  final String? className;
  final String? sectionName;
  final int? classId;
  final int? sectionId;
  final String? rollNumber;

  StudentWithEnrollment({
    required this.id,
    required this.syncId,
    required this.studentCode,
    required this.name,
    this.gender,
    this.dob,
    required this.parentName,
    required this.parentPhone,
    required this.whatsappPhone,
    required this.notificationOptIn,
    required this.enrollmentStatus,
    this.fingerprintId,
    this.className,
    this.sectionName,
    this.classId,
    this.sectionId,
    this.rollNumber,
  });

  factory StudentWithEnrollment.fromRow(QueryRow row) {
    return StudentWithEnrollment(
      id: row.read<int>('id'),
      syncId: row.read<String>('sync_id'),
      studentCode: row.read<String>('student_code'),
      name: row.read<String>('name'),
      gender: row.readNullable<String>('gender'),
      dob: row.readNullable<int>('dob'),
      parentName: row.read<String>('parent_name'),
      parentPhone: row.read<String>('parent_phone'),
      whatsappPhone: row.read<String>('whatsapp_phone'),
      notificationOptIn: row.read<int>('notification_opt_in'),
      enrollmentStatus: row.read<String>('enrollment_status'),
      fingerprintId: row.readNullable<String>('fingerprint_id'),
      className: row.readNullable<String>('class_name'),
      sectionName: row.readNullable<String>('section_name'),
      classId: row.readNullable<int>('class_id'),
      sectionId: row.readNullable<int>('section_id'),
      rollNumber: row.readNullable<String>('roll_number'),
    );
  }
}

class StudentsDao extends DatabaseAccessor<AppDatabase> {
  StudentsDao(super.db);

  Future<List<StudentWithEnrollment>> getAllStudents({
    String? status,
    String? query,
    int? classId,
    int? sectionId,
  }) async {
    final conditions = <String>[];
    final variables = <Variable>[];

    if (status != null && status.isNotEmpty) {
      conditions.add('s.enrollment_status = ?');
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

    if (query != null && query.trim().isNotEmpty) {
      conditions.add('(s.name LIKE ? OR s.student_code LIKE ? OR s.parent_phone LIKE ?)');
      final pattern = '%${query.trim()}%';
      variables.addAll([Variable(pattern), Variable(pattern), Variable(pattern)]);
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final sql = '''
      SELECT s.*, 
             c.name AS class_name, 
             sec.name AS section_name, 
             e.class_id, 
             e.section_id, 
             e.roll_number
      FROM students s
      LEFT JOIN student_enrollments e ON s.id = e.student_id AND e.status = 'active'
      LEFT JOIN school_classes c ON e.class_id = c.id
      LEFT JOIN sections sec ON e.section_id = sec.id
      $whereClause
      ORDER BY s.name ASC
    ''';

    final rows = await customSelect(sql, variables: variables).get();
    return rows.map(StudentWithEnrollment.fromRow).toList();
  }

  Future<StudentWithEnrollment?> getStudentById(int id) async {
    final rows = await customSelect(
      '''
      SELECT s.*, 
             c.name AS class_name, 
             sec.name AS section_name, 
             e.class_id, 
             e.section_id, 
             e.roll_number
      FROM students s
      LEFT JOIN student_enrollments e ON s.id = e.student_id AND e.status = 'active'
      LEFT JOIN school_classes c ON e.class_id = c.id
      LEFT JOIN sections sec ON e.section_id = sec.id
      WHERE s.id = ? LIMIT 1
      ''',
      variables: [Variable(id)],
    ).get();
    if (rows.isEmpty) return null;
    return StudentWithEnrollment.fromRow(rows.first);
  }

  Future<StudentWithEnrollment?> findByCodeOrFingerprint(String code) async {
    final trimmed = code.trim();
    final rows = await customSelect(
      '''
      SELECT s.*, 
             c.name AS class_name, 
             sec.name AS section_name, 
             e.class_id, 
             e.section_id, 
             e.roll_number
      FROM students s
      LEFT JOIN student_enrollments e ON s.id = e.student_id AND e.status = 'active'
      LEFT JOIN school_classes c ON e.class_id = c.id
      LEFT JOIN sections sec ON e.section_id = sec.id
      WHERE s.student_code = ? OR s.fingerprint_id = ? LIMIT 1
      ''',
      variables: [Variable(trimmed), Variable(trimmed)],
    ).get();
    if (rows.isEmpty) return null;
    return StudentWithEnrollment.fromRow(rows.first);
  }

  Future<int> insertStudent({
    required String studentCode,
    required String name,
    String? gender,
    int? dob,
    String parentName = '',
    String parentPhone = '',
    String whatsappPhone = '',
    int notificationOptIn = 1,
    String enrollmentStatus = 'enrolled',
    String? fingerprintId,
    int? createdBy,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO students (
        sync_id, created_at, updated_at, is_synced,
        student_code, name, gender, dob, parent_name,
        parent_phone, whatsapp_phone, notification_opt_in,
        enrollment_status, fingerprint_id, created_by
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(studentCode),
        Variable(name),
        Variable(gender),
        Variable(dob),
        Variable(parentName),
        Variable(parentPhone),
        Variable(whatsappPhone),
        Variable(notificationOptIn),
        Variable(enrollmentStatus),
        Variable(fingerprintId),
        Variable(createdBy),
      ],
    );
  }

  Future<int> updateStudent(
    int id, {
    String? name,
    String? gender,
    int? dob,
    String? parentName,
    String? parentPhone,
    String? whatsappPhone,
    int? notificationOptIn,
    String? enrollmentStatus,
    String? fingerprintId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <String>['updated_at = ?', 'is_synced = 0'];
    final variables = <Variable>[Variable(now)];

    if (name != null) {
      updates.add('name = ?');
      variables.add(Variable(name));
    }
    if (gender != null) {
      updates.add('gender = ?');
      variables.add(Variable(gender));
    }
    if (dob != null) {
      updates.add('dob = ?');
      variables.add(Variable(dob));
    }
    if (parentName != null) {
      updates.add('parent_name = ?');
      variables.add(Variable(parentName));
    }
    if (parentPhone != null) {
      updates.add('parent_phone = ?');
      variables.add(Variable(parentPhone));
    }
    if (whatsappPhone != null) {
      updates.add('whatsapp_phone = ?');
      variables.add(Variable(whatsappPhone));
    }
    if (notificationOptIn != null) {
      updates.add('notification_opt_in = ?');
      variables.add(Variable(notificationOptIn));
    }
    if (enrollmentStatus != null) {
      updates.add('enrollment_status = ?');
      variables.add(Variable(enrollmentStatus));
    }
    if (fingerprintId != null) {
      updates.add('fingerprint_id = ?');
      variables.add(Variable(fingerprintId));
    }

    variables.add(Variable(id));
    return customUpdate(
      'UPDATE students SET ${updates.join(', ')} WHERE id = ?',
      variables: variables,
    );
  }

  Future<int> countActiveStudents() async {
    final rows = await customSelect(
      "SELECT COUNT(*) AS c FROM students WHERE enrollment_status = 'enrolled'",
    ).get();
    return rows.first.read<int>('c');
  }
}
