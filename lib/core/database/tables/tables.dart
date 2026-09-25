import 'package:drift/drift.dart';
import 'sync_columns.dart';

/// Staff and system user accounts with school-specific attendance parameters.
class Users extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get role => text().withDefault(const Constant('staff'))(); // admin, principal, teacher, staff
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get staffCategory => text().withDefault(const Constant('teacher'))(); // teacher, administrator, support_staff
  TextColumn get employeeCode => text().nullable().unique()();
  TextColumn get fingerprintId => text().nullable()();
  TextColumn get expectedStartTime => text().withDefault(const Constant('08:00'))(); // HH:mm format
  IntColumn get gracePeriodMinutes => integer().withDefault(const Constant(15))();
  TextColumn get attendancePolicy => text().withDefault(const Constant('standard'))(); // standard, flexible, strict
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, inactive
  IntColumn get sessionEpoch => integer().withDefault(const Constant(0))();
  TextColumn get photoPath => text().nullable()();
}

/// Students registered in the school.
class Students extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get studentCode => text().unique()(); // e.g. STU-1001
  TextColumn get name => text()();
  TextColumn get gender => text().nullable()(); // male, female, other
  IntColumn get dob => integer().nullable()(); // epoch millis
  TextColumn get parentName => text().withDefault(const Constant(''))();
  TextColumn get parentPhone => text().withDefault(const Constant(''))();
  TextColumn get whatsappPhone => text().withDefault(const Constant(''))();
  IntColumn get notificationOptIn => integer().withDefault(const Constant(1))(); // 1 = true, 0 = false
  TextColumn get enrollmentStatus => text().withDefault(const Constant('enrolled'))(); // enrolled, withdrawn, suspended, graduated
  TextColumn get fingerprintId => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  IntColumn get createdBy => integer().nullable()();
}

/// Academic classes / grades (e.g. Grade 1, Grade 10, Kindergarten).
class SchoolClasses extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get numericGrade => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, inactive
}

/// Sections belonging to a school class (e.g. Section A, Section B, Lily, Rose).
class Sections extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get classId => integer().references(SchoolClasses, #id)();
  TextColumn get name => text()();
  TextColumn get roomNumber => text().nullable()();
  IntColumn get capacity => integer().withDefault(const Constant(40))();
  TextColumn get status => text().withDefault(const Constant('active'))();
}

/// Historical and active class/section enrollment for students.
class StudentEnrollments extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId => integer().references(Students, #id)();
  IntColumn get classId => integer().references(SchoolClasses, #id)();
  IntColumn get sectionId => integer().references(Sections, #id)();
  TextColumn get academicYear => text()(); // e.g. 2026-2027
  TextColumn get rollNumber => text().nullable()();
  IntColumn get startDate => integer()(); // epoch millis
  IntColumn get endDate => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, transferred, completed
}

/// Unified attendance table handling both Students and Staff.
class SchoolAttendances extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get personType => text()(); // student, staff
  IntColumn get studentId => integer().nullable().references(Students, #id)();
  IntColumn get staffId => integer().nullable().references(Users, #id)();
  TextColumn get date => text()(); // YYYY-MM-DD
  IntColumn get checkInTime => integer().nullable()(); // epoch millis
  IntColumn get checkOutTime => integer().nullable()(); // epoch millis
  TextColumn get status => text().withDefault(const Constant('present'))(); // present, late, half_day, absent
  TextColumn get method => text().withDefault(const Constant('fingerprint'))(); // fingerprint, code, manual
  TextColumn get notes => text().nullable()();
  IntColumn get recordedBy => integer().withDefault(const Constant(0))();
}

/// Parent notification queue for absences.
class ParentNotificationJobs extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId => integer().references(Students, #id)();
  TextColumn get date => text()(); // YYYY-MM-DD
  TextColumn get channel => text()(); // sms, whatsapp
  TextColumn get recipientPhone => text()();
  TextColumn get message => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, sent, failed, skipped
  IntColumn get scheduledAt => integer()(); // epoch millis
  IntColumn get sentAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();
}

/// Detailed audit trail of delivery attempts for notification jobs.
class NotificationDeliveryAttempts extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get jobId => integer().references(ParentNotificationJobs, #id)();
  IntColumn get attemptNumber => integer().withDefault(const Constant(1))();
  IntColumn get attemptedAt => integer()(); // epoch millis
  TextColumn get provider => text().withDefault(const Constant('twilio'))();
  TextColumn get providerMessageId => text().nullable()();
  TextColumn get status => text()(); // success, failure
  TextColumn get responseBody => text().nullable()();
}

/// Global school configuration key-value storage.
class SchoolSettings extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()();
  TextColumn get value => text()();
}

/// System-wide activity and audit log.
class ActivityLogs extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // student, staff, attendance, notification, system
  TextColumn get entityId => text().nullable()();
  TextColumn get action => text()(); // create, update, delete, check_in, check_out, send_sms, etc.
  TextColumn get details => text().nullable()();
  IntColumn get performedBy => integer().withDefault(const Constant(0))();
  IntColumn get timestamp => integer()(); // epoch millis
}
