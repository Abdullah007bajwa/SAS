import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class StaffUserData {
  final int id;
  final String syncId;
  final String name;
  final String email;
  final String role;
  final String phone;
  final String staffCategory;
  final String? employeeCode;
  final String? fingerprintId;
  final String expectedStartTime;
  final int gracePeriodMinutes;
  final String attendancePolicy;
  final String status;
  final String? photoPath;

  StaffUserData({
    required this.id,
    required this.syncId,
    required this.name,
    required this.email,
    required this.role,
    required this.phone,
    required this.staffCategory,
    this.employeeCode,
    this.fingerprintId,
    required this.expectedStartTime,
    required this.gracePeriodMinutes,
    required this.attendancePolicy,
    required this.status,
    this.photoPath,
  });

  factory StaffUserData.fromRow(QueryRow row) {
    return StaffUserData(
      id: row.read<int>('id'),
      syncId: row.read<String>('sync_id'),
      name: row.read<String>('name'),
      email: row.read<String>('email'),
      role: row.read<String>('role'),
      phone: row.read<String>('phone'),
      staffCategory: row.read<String>('staff_category'),
      employeeCode: row.readNullable<String>('employee_code'),
      fingerprintId: row.readNullable<String>('fingerprint_id'),
      expectedStartTime: row.read<String>('expected_start_time'),
      gracePeriodMinutes: row.read<int>('grace_period_minutes'),
      attendancePolicy: row.read<String>('attendance_policy'),
      status: row.read<String>('status'),
      photoPath: row.readNullable<String>('photo_path'),
    );
  }
}

class StaffDao extends DatabaseAccessor<AppDatabase> {
  StaffDao(super.db);

  Future<List<StaffUserData>> getAllStaff({
    String? status,
    String? category,
    String? query,
  }) async {
    final conditions = <String>[];
    final variables = <Variable>[];

    if (status != null && status.isNotEmpty) {
      conditions.add('status = ?');
      variables.add(Variable(status));
    }
    if (category != null && category.isNotEmpty) {
      conditions.add('staff_category = ?');
      variables.add(Variable(category));
    }
    if (query != null && query.trim().isNotEmpty) {
      conditions.add('(name LIKE ? OR employee_code LIKE ? OR email LIKE ?)');
      final pattern = '%${query.trim()}%';
      variables.addAll([Variable(pattern), Variable(pattern), Variable(pattern)]);
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await customSelect(
      'SELECT * FROM users $whereClause ORDER BY name ASC',
      variables: variables,
    ).get();
    return rows.map(StaffUserData.fromRow).toList();
  }

  Future<StaffUserData?> getStaffById(int id) async {
    final rows = await customSelect(
      'SELECT * FROM users WHERE id = ? LIMIT 1',
      variables: [Variable(id)],
    ).get();
    if (rows.isEmpty) return null;
    return StaffUserData.fromRow(rows.first);
  }

  Future<StaffUserData?> getStaffByEmployeeCode(String employeeCode) async {
    final trimmed = employeeCode.trim();
    final rows = await customSelect(
      'SELECT * FROM users WHERE employee_code = ? LIMIT 1',
      variables: [Variable(trimmed)],
    ).get();
    if (rows.isEmpty) return null;
    return StaffUserData.fromRow(rows.first);
  }

  Future<StaffUserData?> findByCodeOrFingerprint(String code) async {
    final trimmed = code.trim();
    final rows = await customSelect(
      'SELECT * FROM users WHERE employee_code = ? OR fingerprint_id = ? LIMIT 1',
      variables: [Variable(trimmed), Variable(trimmed)],
    ).get();
    if (rows.isEmpty) return null;
    return StaffUserData.fromRow(rows.first);
  }

  Future<int> insertStaff({
    required String name,
    required String email,
    required String passwordHash,
    String role = 'staff',
    String phone = '',
    String staffCategory = 'teacher',
    String? employeeCode,
    String? fingerprintId,
    String expectedStartTime = '08:00',
    int gracePeriodMinutes = 15,
    String attendancePolicy = 'standard',
    String status = 'active',
    String? photoPath,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO users (
        sync_id, created_at, updated_at, is_synced,
        name, email, password_hash, role, phone,
        staff_category, employee_code, fingerprint_id,
        expected_start_time, grace_period_minutes,
        attendance_policy, status, photo_path
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(name),
        Variable(email),
        Variable(passwordHash),
        Variable(role),
        Variable(phone),
        Variable(staffCategory),
        Variable(employeeCode),
        Variable(fingerprintId),
        Variable(expectedStartTime),
        Variable(gracePeriodMinutes),
        Variable(attendancePolicy),
        Variable(status),
        Variable(photoPath),
      ],
    );
  }

  Future<int> updateStaff(
    int id, {
    String? name,
    String? phone,
    String? role,
    String? staffCategory,
    String? employeeCode,
    String? fingerprintId,
    String? expectedStartTime,
    int? gracePeriodMinutes,
    String? attendancePolicy,
    String? status,
    String? photoPath,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <String>['updated_at = ?', 'is_synced = 0'];
    final variables = <Variable>[Variable(now)];

    if (name != null) {
      updates.add('name = ?');
      variables.add(Variable(name));
    }
    if (phone != null) {
      updates.add('phone = ?');
      variables.add(Variable(phone));
    }
    if (role != null) {
      updates.add('role = ?');
      variables.add(Variable(role));
    }
    if (staffCategory != null) {
      updates.add('staff_category = ?');
      variables.add(Variable(staffCategory));
    }
    if (employeeCode != null) {
      updates.add('employee_code = ?');
      variables.add(Variable(employeeCode));
    }
    if (fingerprintId != null) {
      updates.add('fingerprint_id = ?');
      variables.add(Variable(fingerprintId));
    }
    if (expectedStartTime != null) {
      updates.add('expected_start_time = ?');
      variables.add(Variable(expectedStartTime));
    }
    if (gracePeriodMinutes != null) {
      updates.add('grace_period_minutes = ?');
      variables.add(Variable(gracePeriodMinutes));
    }
    if (attendancePolicy != null) {
      updates.add('attendance_policy = ?');
      variables.add(Variable(attendancePolicy));
    }
    if (status != null) {
      updates.add('status = ?');
      variables.add(Variable(status));
    }
    if (photoPath != null) {
      updates.add('photo_path = ?');
      variables.add(Variable(photoPath.isEmpty ? null : photoPath));
    }

    variables.add(Variable(id));
    return customUpdate(
      'UPDATE users SET ${updates.join(', ')} WHERE id = ?',
      variables: variables,
    );
  }

  Future<int> countActiveStaff() async {
    final rows = await customSelect(
      "SELECT COUNT(*) AS c FROM users WHERE status = 'active'",
    ).get();
    return rows.first.read<int>('c');
  }
}
