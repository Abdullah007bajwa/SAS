import 'dart:developer' as developer;
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../hardware/school_attendance_processor.dart';
import '../services/school_calendar_service.dart';
import 'notification_provider.dart';

class CutoffEvaluationResult {
  final int totalEnrolled;
  final int absencesDetected;
  final int smsJobsCreated;
  final int whatsappJobsCreated;
  final bool isOffDay;

  CutoffEvaluationResult({
    required this.totalEnrolled,
    required this.absencesDetected,
    required this.smsJobsCreated,
    required this.whatsappJobsCreated,
    this.isOffDay = false,
  });
}

class AbsenceCutoffService {
  AbsenceCutoffService({
    required AppDatabase db,
    required SchoolAttendanceProcessor attendanceProcessor,
    required NotificationProvider notificationProvider,
  })  : _db = db,
        _attendanceProcessor = attendanceProcessor,
        _notificationProvider = notificationProvider;

  final AppDatabase _db;
  final SchoolAttendanceProcessor _attendanceProcessor;
  final NotificationProvider _notificationProvider;

  Future<CutoffEvaluationResult> evaluateCutoffAndNotify({DateTime? date}) async {
    final now = date ?? DateTime.now();
    final dateStr = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    developer.log('Running daily cutoff absence evaluation for $dateStr...', name: 'AbsenceCutoffService');

    // 1. Fetch notification and calendar settings
    final settings = await _db.settingsDao.getAllSettings();
    final weeklyOffDays = settings['weekly_off_days'] ?? 'Sunday';
    final holidays = settings['school_holidays'];

    // Check if today is a scheduled off-day (Sunday or holiday)
    if (SchoolCalendarService.isOffDay(now, weeklyOffDays: weeklyOffDays, holidaysStr: holidays)) {
      developer.log('Date $dateStr is a scheduled off-day/weekend. Skipping absence cutoff evaluation.', name: 'AbsenceCutoffService');
      return CutoffEvaluationResult(
        totalEnrolled: 0,
        absencesDetected: 0,
        smsJobsCreated: 0,
        whatsappJobsCreated: 0,
        isOffDay: true,
      );
    }

    // 2. Mandatory Step: Perform a final K50 poll to flush all pending logs
    await _attendanceProcessor.poll();

    final smsEnabled = settings['sms_enabled'] == 'true';
    final whatsappEnabled = settings['whatsapp_enabled'] == 'true';
    final smsTemplate = settings['absence_sms_template'] ??
        'Dear Parent, your child {student_name} is marked ABSENT today ({date}).';
    final whatsappTemplate = settings['absence_whatsapp_template'] ??
        'Dear Parent, your child {student_name} is marked ABSENT today ({date}).';

    // 3. Query all currently enrolled students
    final enrolledStudents = await _db.studentsDao.getAllStudents(status: 'enrolled');

    var absencesCount = 0;
    var smsCount = 0;
    var whatsappCount = 0;

    for (final student in enrolledStudents) {
      final existingAttendance = await _db.attendanceDao.getStudentAttendanceToday(student.id, dateStr);

      if (existingAttendance != null && existingAttendance.readNullable<int>('check_in_time') != null) {
        // Student was scanned and is present/late today
        continue;
      }

      absencesCount++;

      // Record absence in school_attendances if not recorded yet
      if (existingAttendance == null) {
        await _db.customInsert(
          '''
          INSERT INTO school_attendances (
            sync_id, created_at, updated_at, is_synced,
            person_type, student_id, staff_id, date,
            check_in_time, check_out_time, status, method, recorded_by
          ) VALUES (?, ?, ?, 0, 'student', ?, NULL, ?, NULL, NULL, 'absent', 'system', 0)
          ''',
          variables: [
            Variable('abs_${student.id}_$dateStr'),
            Variable(now.millisecondsSinceEpoch),
            Variable(now.millisecondsSinceEpoch),
            Variable(student.id),
            Variable(dateStr),
          ],
        );
      }

      // Check notification opt-in
      if (student.notificationOptIn != 1) continue;

      // Handle SMS notification
      if (smsEnabled && student.parentPhone.trim().isNotEmpty) {
        final hasSms = await _db.notificationsDao.hasJobForStudentDateChannel(student.id, dateStr, 'sms');
        if (!hasSms) {
          final body = _formatMessage(smsTemplate, student.name, dateStr);
          final jobId = await _db.notificationsDao.createJob(
            studentId: student.id,
            date: dateStr,
            channel: 'sms',
            recipientPhone: student.parentPhone.trim(),
            message: body,
          );
          smsCount++;

          // Dispatch SMS
          final result = await _notificationProvider.sendSms(
            to: student.parentPhone.trim(),
            message: body,
            credentials: settings,
          );

          await _db.notificationsDao.recordAttempt(
            jobId: jobId,
            attemptNumber: 1,
            provider: _notificationProvider.name,
            providerMessageId: result.messageId,
            status: result.success ? 'success' : 'failure',
            responseBody: result.error ?? result.rawResponse,
          );

          await _db.notificationsDao.updateJobStatus(
            jobId,
            result.success ? 'sent' : 'failed',
            sentAt: result.success ? DateTime.now().millisecondsSinceEpoch : null,
            lastError: result.error,
          );
        }
      }

      // Handle WhatsApp notification
      if (whatsappEnabled && student.whatsappPhone.trim().isNotEmpty) {
        final hasWa = await _db.notificationsDao.hasJobForStudentDateChannel(student.id, dateStr, 'whatsapp');
        if (!hasWa) {
          final body = _formatMessage(whatsappTemplate, student.name, dateStr);
          final jobId = await _db.notificationsDao.createJob(
            studentId: student.id,
            date: dateStr,
            channel: 'whatsapp',
            recipientPhone: student.whatsappPhone.trim(),
            message: body,
          );
          whatsappCount++;

          // Dispatch WhatsApp
          final result = await _notificationProvider.sendWhatsApp(
            to: student.whatsappPhone.trim(),
            message: body,
            credentials: settings,
          );

          await _db.notificationsDao.recordAttempt(
            jobId: jobId,
            attemptNumber: 1,
            provider: _notificationProvider.name,
            providerMessageId: result.messageId,
            status: result.success ? 'success' : 'failure',
            responseBody: result.error ?? result.rawResponse,
          );

          await _db.notificationsDao.updateJobStatus(
            jobId,
            result.success ? 'sent' : 'failed',
            sentAt: result.success ? DateTime.now().millisecondsSinceEpoch : null,
            lastError: result.error,
          );
        }
      }
    }

    await _db.activityDao.log(
      entityType: 'notification',
      action: 'cutoff_evaluation',
      details: 'Cutoff evaluation for $dateStr complete: $absencesCount absent, $smsCount SMS sent, $whatsappCount WhatsApp sent.',
    );

    return CutoffEvaluationResult(
      totalEnrolled: enrolledStudents.length,
      absencesDetected: absencesCount,
      smsJobsCreated: smsCount,
      whatsappJobsCreated: whatsappCount,
    );
  }

  String _formatMessage(String template, String studentName, String date) {
    return template
        .replaceAll('{student_name}', studentName)
        .replaceAll('{date}', date);
  }
}
