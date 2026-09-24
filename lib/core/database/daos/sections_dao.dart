import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class SectionData {
  final int id;
  final String syncId;
  final int classId;
  final String className;
  final String name;
  final String? roomNumber;
  final int capacity;
  final String status;
  final int studentCount;

  SectionData({
    required this.id,
    required this.syncId,
    required this.classId,
    required this.className,
    required this.name,
    this.roomNumber,
    required this.capacity,
    required this.status,
    required this.studentCount,
  });

  factory SectionData.fromRow(QueryRow row) {
    return SectionData(
      id: row.read<int>('id'),
      syncId: row.read<String>('sync_id'),
      classId: row.read<int>('class_id'),
      className: row.read<String>('class_name'),
      name: row.read<String>('name'),
      roomNumber: row.readNullable<String>('room_number'),
      capacity: row.read<int>('capacity'),
      status: row.read<String>('status'),
      studentCount: row.read<int>('student_count'),
    );
  }
}

class SectionsDao extends DatabaseAccessor<AppDatabase> {
  SectionsDao(super.db);

  Future<List<SectionData>> getSectionsByClassId(int classId) async {
    final rows = await customSelect(
      '''
      SELECT s.*, 
             c.name AS class_name, 
             COUNT(DISTINCT e.student_id) AS student_count
      FROM sections s
      JOIN school_classes c ON s.class_id = c.id
      LEFT JOIN student_enrollments e ON s.id = e.section_id AND e.status = 'active'
      WHERE s.class_id = ?
      GROUP BY s.id
      ORDER BY s.name ASC
      ''',
      variables: [Variable(classId)],
    ).get();
    return rows.map(SectionData.fromRow).toList();
  }

  Future<List<SectionData>> getAllSections() async {
    final rows = await customSelect(
      '''
      SELECT s.*, 
             c.name AS class_name, 
             COUNT(DISTINCT e.student_id) AS student_count
      FROM sections s
      JOIN school_classes c ON s.class_id = c.id
      LEFT JOIN student_enrollments e ON s.id = e.section_id AND e.status = 'active'
      GROUP BY s.id
      ORDER BY c.numeric_grade ASC, c.name ASC, s.name ASC
      ''',
    ).get();
    return rows.map(SectionData.fromRow).toList();
  }

  Future<int> insertSection({
    required int classId,
    required String name,
    String? roomNumber,
    int capacity = 40,
    String status = 'active',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO sections (
        sync_id, created_at, updated_at, is_synced,
        class_id, name, room_number, capacity, status
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(classId),
        Variable(name),
        Variable(roomNumber),
        Variable(capacity),
        Variable(status),
      ],
    );
  }

  Future<int> updateSection(
    int id, {
    String? name,
    String? roomNumber,
    int? capacity,
    String? status,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <String>['updated_at = ?', 'is_synced = 0'];
    final variables = <Variable>[Variable(now)];

    if (name != null) {
      updates.add('name = ?');
      variables.add(Variable(name));
    }
    if (roomNumber != null) {
      updates.add('room_number = ?');
      variables.add(Variable(roomNumber));
    }
    if (capacity != null) {
      updates.add('capacity = ?');
      variables.add(Variable(capacity));
    }
    if (status != null) {
      updates.add('status = ?');
      variables.add(Variable(status));
    }

    variables.add(Variable(id));
    return customUpdate(
      'UPDATE sections SET ${updates.join(', ')} WHERE id = ?',
      variables: variables,
    );
  }
}
