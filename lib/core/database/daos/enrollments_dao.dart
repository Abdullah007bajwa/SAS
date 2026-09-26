import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class StudentEnrollmentsDao extends DatabaseAccessor<AppDatabase> {
  StudentEnrollmentsDao(super.db);

  Future<int> enrollStudent({
    required int studentId,
    required int classId,
    required int sectionId,
    required String academicYear,
    String? rollNumber,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    // Mark previous active enrollments as completed/transferred
    await customUpdate(
      '''
      UPDATE student_enrollments 
      SET status = 'transferred', end_date = ?, updated_at = ?, is_synced = 0
      WHERE student_id = ? AND status = 'active'
      ''',
      variables: [Variable(now), Variable(now), Variable(studentId)],
    );

    return customInsert(
      '''
      INSERT INTO student_enrollments (
        sync_id, created_at, updated_at, is_synced,
        student_id, class_id, section_id, academic_year,
        roll_number, start_date, status
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, 'active')
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(studentId),
        Variable(classId),
        Variable(sectionId),
        Variable(academicYear),
        Variable(rollNumber),
        Variable(now),
      ],
    );
  }

  Future<int> countEnrolledInClassSection(int classId, int sectionId) async {
    final rows = await customSelect(
      '''
      SELECT COUNT(*) AS c 
      FROM student_enrollments 
      WHERE class_id = ? AND section_id = ? AND status = 'active'
      ''',
      variables: [Variable(classId), Variable(sectionId)],
    ).get();
    return rows.first.read<int>('c');
  }
}
