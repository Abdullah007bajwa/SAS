import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Opens the on-device SQLite database with WAL enabled for School Attendance Portal.
QueryExecutor openAppDatabaseConnection() {
  return driftDatabase(name: 'school_attendance');
}
