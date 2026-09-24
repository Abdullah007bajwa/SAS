import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class SchoolClassData {
  final int id;
  final String syncId;
  final String name;
  final int? numericGrade;
  final String? description;
  final String status;
  final int studentCount;

  SchoolClassData({
    required this.id,
    required this.syncId,
    required this.name,
    this.numericGrade,
    this.description,
    required this.status,
    required this.studentCount,
  });

  factory SchoolClassData.fromRow(QueryRow row) {
    return SchoolClassData(
      id: row.read<int>('id'),
      syncId: row.read<String>('sync_id'),
      name: row.read<String>('name'),
      numericGrade: row.readNullable<int>('numeric_grade'),
      description: row.readNullable<String>('description'),
      status: row.read<String>('status'),
      studentCount: row.read<int>('student_count'),
    );
  }
}

class ClassesDao extends DatabaseAccessor<AppDatabase> {
  ClassesDao(super.db);

  Future<List<SchoolClassData>> getAllClasses() async {
    final rows = await customSelect(
      '''
      SELECT c.*, 
             COUNT(DISTINCT e.student_id) AS student_count
      FROM school_classes c
      LEFT JOIN student_enrollments e ON c.id = e.class_id AND e.status = 'active'
      GROUP BY c.id
      ORDER BY c.numeric_grade ASC, c.name ASC
      ''',
    ).get();
    return rows.map(SchoolClassData.fromRow).toList();
  }

  Future<SchoolClassData?> getClassById(int id) async {
    final rows = await customSelect(
      '''
      SELECT c.*, 
             COUNT(DISTINCT e.student_id) AS student_count
      FROM school_classes c
      LEFT JOIN student_enrollments e ON c.id = e.class_id AND e.status = 'active'
      WHERE c.id = ?
      GROUP BY c.id
      LIMIT 1
      ''',
      variables: [Variable(id)],
    ).get();
    if (rows.isEmpty) return null;
    return SchoolClassData.fromRow(rows.first);
  }

  Future<int> insertClass({
    required String name,
    int? numericGrade,
    String? description,
    String status = 'active',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO school_classes (
        sync_id, created_at, updated_at, is_synced,
        name, numeric_grade, description, status
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(name),
        Variable(numericGrade),
        Variable(description),
        Variable(status),
      ],
    );
  }

  Future<int> updateClass(
    int id, {
    String? name,
    int? numericGrade,
    String? description,
    String? status,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <String>['updated_at = ?', 'is_synced = 0'];
    final variables = <Variable>[Variable(now)];

    if (name != null) {
      updates.add('name = ?');
      variables.add(Variable(name));
    }
    if (numericGrade != null) {
      updates.add('numeric_grade = ?');
      variables.add(Variable(numericGrade));
    }
    if (description != null) {
      updates.add('description = ?');
      variables.add(Variable(description));
    }
    if (status != null) {
      updates.add('status = ?');
      variables.add(Variable(status));
    }

    variables.add(Variable(id));
    return customUpdate(
      'UPDATE school_classes SET ${updates.join(', ')} WHERE id = ?',
      variables: variables,
    );
  }
}
