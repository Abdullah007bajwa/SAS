import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

QueryExecutor openAppDatabaseConnection() {
  return driftDatabase(name: 'school_attendance');
}
