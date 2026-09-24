import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../database/daos/students_dao.dart';
import '../database/daos/staff_dao.dart';
import 'k50_attendance_push_service.dart';
import 'k50_device_user_map.dart';
import 'zk_attendance_dedup.dart';
import 'zk_backend_client.dart';
import 'zk_device_service.dart';

/// School attendance processor that sits directly above the K50 event boundary.
/// Classifies raw device events as Student or Staff punches, evaluates arrival policies,
/// records attendance, and prevents duplicates.
class SchoolAttendanceProcessor {
  SchoolAttendanceProcessor({
    required AppDatabase db,
    required ZkBackendClient backendClient,
    required ZkAttendanceDedup dedup,
    required K50DeviceUserMap deviceUserMap,
    this.onAttendanceChanged,
  })  : _db = db,
        _backendClient = backendClient,
        _dedup = dedup,
        _deviceUserMap = deviceUserMap;

  final AppDatabase _db;
  final ZkBackendClient _backendClient;
  final ZkAttendanceDedup _dedup;
  final K50DeviceUserMap _deviceUserMap;
  final VoidCallback? onAttendanceChanged;

  Timer? _timer;
  K50AttendancePushService? _pushService;
  late Set<String> _processedKeys;

  bool _isProcessing = false;

  void start(String bridgeBaseUrl) {
    _processedKeys = _dedup.load();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => poll());

    _pushService?.stop();
    _pushService = K50AttendancePushService(
      onLog: (log) => unawaited(applyLogs([log])),
    )..start([bridgeBaseUrl]);

    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;

    _pushService?.stop();
    _pushService = null;
  }

  Future<void> poll() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final logs = await _backendClient.pullAttendanceLogs();
      if (logs.isNotEmpty) {
        await applyLogs(logs);
      }
    } catch (e, st) {
      developer.log(
        'K50 attendance poll failed',
        name: 'SchoolAttendanceProcessor',
        error: e,
        stackTrace: st,
      );
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> applyLogs(List<LogEntry> logs) async {
    if (logs.isEmpty) return;

    var changed = false;

    // Load active settings for cutoff and ID ranges
    final cutoffStr = await _db.settingsDao.getSetting('student_cutoff_time', defaultValue: '08:30');
    final studentRangeStart = int.tryParse(await _db.settingsDao.getSetting('student_id_range_start', defaultValue: '1001')) ?? 1001;
    final studentRangeEnd = int.tryParse(await _db.settingsDao.getSetting('student_id_range_end', defaultValue: '7999')) ?? 7999;
    final staffRangeStart = int.tryParse(await _db.settingsDao.getSetting('staff_id_range_start', defaultValue: '8001')) ?? 8001;
    final staffRangeEnd = int.tryParse(await _db.settingsDao.getSetting('staff_id_range_end', defaultValue: '8999')) ?? 8999;

    for (final log in logs) {
      try {
        final rawId = (log.deviceUserId != null && log.deviceUserId!.trim().isNotEmpty)
            ? log.deviceUserId!.trim()
            : log.userId.trim();

        if (rawId.isEmpty) continue;

        final dedupKey = '${rawId}_${log.timestamp.millisecondsSinceEpoch}';
        if (_dedup.contains(_processedKeys, dedupKey)) continue;

        final numericId = int.tryParse(rawId);

        // 1. Check mapped code
        final mappedCode = _deviceUserMap.appCodeForDeviceUser(rawId);

        // 2. Classify candidate role
        bool isStaffCandidate = false;
        bool isStudentCandidate = false;

        if (numericId != null) {
          if (numericId >= staffRangeStart && numericId <= staffRangeEnd) {
            isStaffCandidate = true;
          } else if (numericId >= studentRangeStart && numericId <= studentRangeEnd) {
            isStudentCandidate = true;
          }
        }

        // Try Staff resolution first if candidate or fallback
        StaffUserData? staff;
        if (isStaffCandidate || !isStudentCandidate) {
          staff = await _resolveStaff(rawId, mappedCode, numericId);
        }

        if (staff != null) {
          // Process Staff punch
          final isLate = _isStaffLate(log.timestamp, staff.expectedStartTime, staff.gracePeriodMinutes);
          final status = isLate ? 'late' : 'present';

          await _db.attendanceDao.recordStaffPunch(
            staffId: staff.id,
            timestamp: log.timestamp,
            status: status,
            method: 'fingerprint',
          );

          _dedup.add(_processedKeys, dedupKey);
          changed = true;
          continue;
        }

        // Try Student resolution
        final student = await _resolveStudent(rawId, mappedCode, numericId);
        if (student != null) {
          // Process Student check-in
          final isLate = _isStudentLate(log.timestamp, cutoffStr);
          final status = isLate ? 'late' : 'present';

          await _db.attendanceDao.recordStudentCheckIn(
            studentId: student.id,
            timestamp: log.timestamp,
            status: status,
            method: 'fingerprint',
          );

          _dedup.add(_processedKeys, dedupKey);
          changed = true;
          continue;
        }

        developer.log(
          'K50 scan unmatched to any student or staff member: rawId=$rawId',
          name: 'SchoolAttendanceProcessor',
        );
      } catch (e, st) {
        developer.log(
          'Error processing K50 log entry: ${log.userId}',
          name: 'SchoolAttendanceProcessor',
          error: e,
          stackTrace: st,
        );
      }
    }

    if (changed) {
      await _dedup.save(_processedKeys);
      onAttendanceChanged?.call();
    }
  }

  Future<StaffUserData?> _resolveStaff(String rawId, String? mappedCode, int? numericId) async {
    final candidates = <String>{rawId};
    if (mappedCode != null) candidates.add(mappedCode);
    if (numericId != null) {
      candidates.add('EMP-$numericId');
      candidates.add('TCH-$numericId');
      candidates.add('EMP${numericId.toString().padLeft(4, '0')}');
    }

    for (final code in candidates) {
      final staff = await _db.staffDao.findByCodeOrFingerprint(code);
      if (staff != null) return staff;
    }
    return null;
  }

  Future<StudentWithEnrollment?> _resolveStudent(String rawId, String? mappedCode, int? numericId) async {
    final candidates = <String>{rawId};
    if (mappedCode != null) candidates.add(mappedCode);
    if (numericId != null) {
      candidates.add('STU-$numericId');
      candidates.add('STU${numericId.toString().padLeft(4, '0')}');
    }

    for (final code in candidates) {
      final student = await _db.studentsDao.findByCodeOrFingerprint(code);
      if (student != null) return student;
    }
    return null;
  }

  bool _isStudentLate(DateTime scanTime, String cutoffStr) {
    try {
      final parts = cutoffStr.split(':');
      if (parts.length >= 2) {
        final cutoffHour = int.parse(parts[0].trim());
        final cutoffMin = int.parse(parts[1].trim());
        final cutoff = DateTime(
          scanTime.year,
          scanTime.month,
          scanTime.day,
          cutoffHour,
          cutoffMin,
        );
        return scanTime.isAfter(cutoff);
      }
    } catch (_) {}
    return false;
  }

  bool _isStaffLate(DateTime scanTime, String expectedStart, int graceMinutes) {
    try {
      final parts = expectedStart.split(':');
      if (parts.length >= 2) {
        final startHour = int.parse(parts[0].trim());
        final startMin = int.parse(parts[1].trim());
        final deadline = DateTime(
          scanTime.year,
          scanTime.month,
          scanTime.day,
          startHour,
          startMin,
        ).add(Duration(minutes: graceMinutes));
        return scanTime.isAfter(deadline);
      }
    } catch (_) {}
    return false;
  }
}
