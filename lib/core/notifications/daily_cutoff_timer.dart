import 'dart:async';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import 'absence_cutoff_service.dart';

/// Periodic timer that monitors the daily student cutoff time and triggers absence processing.
class DailyCutoffTimer {
  DailyCutoffTimer({
    required AppDatabase db,
    required AbsenceCutoffService cutoffService,
    required SharedPreferences prefs,
  })  : _db = db,
        _cutoffService = cutoffService,
        _prefs = prefs;

  final AppDatabase _db;
  final AbsenceCutoffService _cutoffService;
  final SharedPreferences _prefs;

  Timer? _timer;
  static const _lastRunDateKey = 'sas_last_cutoff_run_date';

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => checkCutoff());
    checkCutoff();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> checkCutoff() async {
    final now = DateTime.now();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final lastRunDate = _prefs.getString(_lastRunDateKey);
    if (lastRunDate == todayStr) {
      // Already executed for today
      return;
    }

    final cutoffTimeStr = await _db.settingsDao.getSetting('student_cutoff_time', defaultValue: '08:30');
    final parts = cutoffTimeStr.split(':');
    if (parts.length < 2) return;

    final cutoffHour = int.tryParse(parts[0].trim()) ?? 8;
    final cutoffMin = int.tryParse(parts[1].trim()) ?? 30;

    final cutoffDateTime = DateTime(now.year, now.month, now.day, cutoffHour, cutoffMin);

    if (now.isAfter(cutoffDateTime)) {
      developer.log('Daily cutoff time reached ($cutoffTimeStr). Triggering absence evaluation...', name: 'DailyCutoffTimer');
      try {
        await _cutoffService.evaluateCutoffAndNotify(date: now);
        await _prefs.setString(_lastRunDateKey, todayStr);
      } catch (e, st) {
        developer.log('Error executing daily cutoff timer job', name: 'DailyCutoffTimer', error: e, stackTrace: st);
      }
    }
  }
}
