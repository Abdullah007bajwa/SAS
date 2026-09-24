import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';

const _uuid = Uuid();

class NotificationJobView {
  final int id;
  final String syncId;
  final int studentId;
  final String studentName;
  final String studentCode;
  final String? className;
  final String? sectionName;
  final String date;
  final String channel;
  final String recipientPhone;
  final String message;
  final String status;
  final int scheduledAt;
  final int? sentAt;
  final String? lastError;

  NotificationJobView({
    required this.id,
    required this.syncId,
    required this.studentId,
    required this.studentName,
    required this.studentCode,
    this.className,
    this.sectionName,
    required this.date,
    required this.channel,
    required this.recipientPhone,
    required this.message,
    required this.status,
    required this.scheduledAt,
    this.sentAt,
    this.lastError,
  });

  factory NotificationJobView.fromRow(QueryRow row) {
    return NotificationJobView(
      id: row.read<int>('id'),
      syncId: row.read<String>('sync_id'),
      studentId: row.read<int>('student_id'),
      studentName: row.read<String>('student_name'),
      studentCode: row.read<String>('student_code'),
      className: row.readNullable<String>('class_name'),
      sectionName: row.readNullable<String>('section_name'),
      date: row.read<String>('date'),
      channel: row.read<String>('channel'),
      recipientPhone: row.read<String>('recipient_phone'),
      message: row.read<String>('message'),
      status: row.read<String>('status'),
      scheduledAt: row.read<int>('scheduled_at'),
      sentAt: row.readNullable<int>('sent_at'),
      lastError: row.readNullable<String>('last_error'),
    );
  }
}

class NotificationsDao extends DatabaseAccessor<AppDatabase> {
  NotificationsDao(super.db);

  Future<bool> hasJobForStudentDateChannel(int studentId, String date, String channel) async {
    final rows = await customSelect(
      '''
      SELECT id FROM parent_notification_jobs
      WHERE student_id = ? AND date = ? AND channel = ?
      LIMIT 1
      ''',
      variables: [Variable(studentId), Variable(date), Variable(channel)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<int> createJob({
    required int studentId,
    required String date,
    required String channel,
    required String recipientPhone,
    required String message,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO parent_notification_jobs (
        sync_id, created_at, updated_at, is_synced,
        student_id, date, channel, recipient_phone,
        message, status, scheduled_at
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, 'pending', ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(studentId),
        Variable(date),
        Variable(channel),
        Variable(recipientPhone),
        Variable(message),
        Variable(now),
      ],
    );
  }

  Future<void> updateJobStatus(
    int jobId,
    String status, {
    int? sentAt,
    String? lastError,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = <String>['status = ?', 'updated_at = ?', 'is_synced = 0'];
    final variables = <Variable>[Variable(status), Variable(now)];

    if (sentAt != null) {
      updates.add('sent_at = ?');
      variables.add(Variable(sentAt));
    }
    if (lastError != null) {
      updates.add('last_error = ?');
      variables.add(Variable(lastError));
    }

    variables.add(Variable(jobId));
    await customUpdate(
      'UPDATE parent_notification_jobs SET ${updates.join(', ')} WHERE id = ?',
      variables: variables,
    );
  }

  Future<int> recordAttempt({
    required int jobId,
    required int attemptNumber,
    required String provider,
    String? providerMessageId,
    required String status,
    String? responseBody,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncId = _uuid.v4();

    return customInsert(
      '''
      INSERT INTO notification_delivery_attempts (
        sync_id, created_at, updated_at, is_synced,
        job_id, attempt_number, attempted_at, provider,
        provider_message_id, status, response_body
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable(syncId),
        Variable(now),
        Variable(now),
        Variable(jobId),
        Variable(attemptNumber),
        Variable(now),
        Variable(provider),
        Variable(providerMessageId),
        Variable(status),
        Variable(responseBody),
      ],
    );
  }

  Future<List<NotificationJobView>> getNotificationHistory({
    String? date,
    String? channel,
    String? status,
  }) async {
    final conditions = <String>[];
    final variables = <Variable>[];

    if (date != null && date.isNotEmpty) {
      conditions.add('j.date = ?');
      variables.add(Variable(date));
    }
    if (channel != null && channel.isNotEmpty) {
      conditions.add('j.channel = ?');
      variables.add(Variable(channel));
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('j.status = ?');
      variables.add(Variable(status));
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final sql = '''
      SELECT j.*,
             s.name AS student_name,
             s.student_code,
             c.name AS class_name,
             sec.name AS section_name
      FROM parent_notification_jobs j
      JOIN students s ON j.student_id = s.id
      LEFT JOIN student_enrollments e ON s.id = e.student_id AND e.status = 'active'
      LEFT JOIN school_classes c ON e.class_id = c.id
      LEFT JOIN sections sec ON e.section_id = sec.id
      $whereClause
      ORDER BY j.scheduled_at DESC
    ''';

    final rows = await customSelect(sql, variables: variables).get();
    return rows.map(NotificationJobView.fromRow).toList();
  }
}
