import 'dart:async';
import 'dart:developer' as developer;
import '../database/app_database.dart';
import 'android_gateway_notification_provider.dart';
import 'notification_provider.dart';
import 'twilio_notification_provider.dart';

/// Background dispatcher that processes the SMS/notification queue sequentially.
///
/// Implements carrier-safe rate limiting (2.5s - 3s delay) to avoid automated
/// spam blocks on local Pakistani SIM cards (Jazz, Zong, Telenor, Ufone).
class SmsQueueDispatcher {
  SmsQueueDispatcher({
    required AppDatabase db,
    AndroidGatewayNotificationProvider? gatewayProvider,
    TwilioNotificationProvider? twilioProvider,
  })  : _db = db,
        _gatewayProvider = gatewayProvider ?? AndroidGatewayNotificationProvider(),
        _twilioProvider = twilioProvider ?? TwilioNotificationProvider();

  final AppDatabase _db;
  final AndroidGatewayNotificationProvider _gatewayProvider;
  final TwilioNotificationProvider _twilioProvider;

  Timer? _pollTimer;
  bool _isProcessing = false;
  bool _stopped = false;

  void start() {
    _stopped = false;
    _pollTimer?.cancel();
    // Check queue every 5 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => processPendingQueue());
    // Initial check
    processPendingQueue();
  }

  void stop() {
    _stopped = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Manually wake up the queue (e.g., right after new attendance punch).
  void trigger() {
    if (!_isProcessing && !_stopped) {
      unawaited(processPendingQueue());
    }
  }

  Future<void> processPendingQueue() async {
    if (_isProcessing || _stopped) return;
    _isProcessing = true;

    try {
      final settings = await _db.settingsDao.getAllSettings();
      final isSmsEnabled = settings['sms_enabled'] == 'true';
      if (!isSmsEnabled) return;

      final providerName = settings['sms_provider'] ?? 'android_gateway';
      final delaySec = double.tryParse(settings['sms_throttle_delay_sec'] ?? '2.5') ?? 2.5;

      final NotificationProvider provider = providerName == 'twilio'
          ? _twilioProvider
          : _gatewayProvider;

      // Fetch all pending SMS jobs ordered by scheduled time
      final pendingJobs = await _db.notificationsDao.getNotificationHistory(
        channel: 'sms',
        status: 'pending',
      );

      if (pendingJobs.isEmpty) return;

      developer.log(
        'Processing ${pendingJobs.length} pending SMS notifications via ${provider.name}...',
        name: 'SmsQueueDispatcher',
      );

      for (final job in pendingJobs) {
        if (_stopped) break;

        final result = await provider.sendSms(
          to: job.recipientPhone,
          message: job.message,
          credentials: settings,
        );

        final now = DateTime.now().millisecondsSinceEpoch;

        if (result.success) {
          await _db.notificationsDao.updateJobStatus(
            job.id,
            'sent',
            sentAt: now,
          );
          await _db.notificationsDao.recordAttempt(
            jobId: job.id,
            attemptNumber: 1,
            provider: provider.name,
            providerMessageId: result.messageId,
            status: 'success',
            responseBody: result.rawResponse,
          );

          developer.log(
            'SMS sent successfully to ${job.recipientPhone} (job #${job.id})',
            name: 'SmsQueueDispatcher',
          );

          // CARRIER SAFETY DELAY: 2.5s spacing between SMS dispatches
          if (delaySec > 0) {
            await Future.delayed(Duration(milliseconds: (delaySec * 1000).toInt()));
          }
        } else {
          developer.log(
            'SMS failed for ${job.recipientPhone}: ${result.error}',
            name: 'SmsQueueDispatcher',
          );

          await _db.notificationsDao.updateJobStatus(
            job.id,
            'failed',
            lastError: result.error,
          );
          await _db.notificationsDao.recordAttempt(
            jobId: job.id,
            attemptNumber: 1,
            provider: provider.name,
            status: 'failure',
            responseBody: result.error,
          );

          // If connection to Android phone failed, pause 6 seconds before trying next job
          if (result.error?.contains('Cannot connect') == true) {
            await Future.delayed(const Duration(seconds: 6));
          }
        }
      }
    } catch (e, st) {
      developer.log(
        'Queue processing error: $e',
        name: 'SmsQueueDispatcher',
        error: e,
        stackTrace: st,
      );
    } finally {
      _isProcessing = false;
    }
  }

  /// Sends a single test SMS and returns immediate status.
  Future<NotificationSendResult> sendTestSms({
    required String to,
    required String message,
  }) async {
    final settings = await _db.settingsDao.getAllSettings();
    final providerName = settings['sms_provider'] ?? 'android_gateway';

    final NotificationProvider provider = providerName == 'twilio'
        ? _twilioProvider
        : _gatewayProvider;

    return provider.sendSms(
      to: to,
      message: message,
      credentials: settings,
    );
  }
}
