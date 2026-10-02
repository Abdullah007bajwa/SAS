import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_provider.dart';
import '../hardware/hardware_providers.dart';
import 'absence_cutoff_service.dart';
import 'daily_cutoff_timer.dart';
import 'android_gateway_notification_provider.dart';
import 'notification_provider.dart';
import 'sms_queue_dispatcher.dart';
import 'twilio_notification_provider.dart';

final androidGatewayNotificationProvider = Provider<AndroidGatewayNotificationProvider>((ref) {
  return AndroidGatewayNotificationProvider();
});

final twilioNotificationProvider = Provider<TwilioNotificationProvider>((ref) {
  return TwilioNotificationProvider();
});

final notificationProviderProvider = Provider<NotificationProvider>((ref) {
  return ref.watch(androidGatewayNotificationProvider);
});

final smsQueueDispatcherProvider = Provider<SmsQueueDispatcher>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final gateway = ref.watch(androidGatewayNotificationProvider);
  final twilio = ref.watch(twilioNotificationProvider);

  return SmsQueueDispatcher(
    db: db,
    gatewayProvider: gateway,
    twilioProvider: twilio,
  );
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
