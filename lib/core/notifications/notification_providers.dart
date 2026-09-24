import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_provider.dart';
import '../hardware/hardware_providers.dart';
import 'absence_cutoff_service.dart';
import 'daily_cutoff_timer.dart';
import 'notification_provider.dart';
import 'twilio_notification_provider.dart';

final notificationProviderProvider = Provider<NotificationProvider>((ref) {
  return TwilioNotificationProvider();
});

final absenceCutoffServiceProvider = Provider<AbsenceCutoffService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final processor = ref.watch(schoolAttendanceProcessorProvider);
  final provider = ref.watch(notificationProviderProvider);

  return AbsenceCutoffService(
    db: db,
    attendanceProcessor: processor,
    notificationProvider: provider,
  );
});

final dailyCutoffTimerProvider = Provider<DailyCutoffTimer>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final cutoffService = ref.watch(absenceCutoffServiceProvider);
  final prefs = ref.watch(sharedPreferencesProvider);

  return DailyCutoffTimer(
    db: db,
    cutoffService: cutoffService,
    prefs: prefs,
  );
});
