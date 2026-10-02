import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:school_attendance_portal/core/database/app_database.dart';
import 'package:school_attendance_portal/core/notifications/android_gateway_notification_provider.dart';
import 'package:school_attendance_portal/core/notifications/sms_queue_dispatcher.dart';
import '../test_helper.dart';

class MockHttpClient extends http.BaseClient {
  http.Request? lastRequest;
  String? lastRequestBody;
  int statusCode = 200;
  String responseBody = '{"id": "MSG_1001", "status": "sent"}';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      lastRequest = request;
      lastRequestBody = request.body;
    }
    final bytes = utf8.encode(responseBody);
    return http.StreamedResponse(
      Stream.value(bytes),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  setupSqliteForTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MockHttpClient mockHttp;
  late AndroidGatewayNotificationProvider gateway;
  late SmsQueueDispatcher dispatcher;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockHttp = MockHttpClient();
    gateway = AndroidGatewayNotificationProvider(client: mockHttp);
    dispatcher = SmsQueueDispatcher(
      db: db,
      gatewayProvider: gateway,
    );
  });

  tearDown(() async {
    dispatcher.stop();
    await db.close();
  });

  group('AndroidGatewayNotificationProvider', () {
    test('sends SMS payload and parses messageId successfully', () async {
      final res = await gateway.sendSms(
        to: '0300-1234567',
        message: 'Hello Student Arrived',
        credentials: {
          'sms_gateway_url': 'http://192.168.18.50:8080',
          'sms_gateway_username': 'admin',
          'sms_gateway_password': 'secretpassword',
        },
      );

      expect(res.success, isTrue);
      expect(res.messageId, 'MSG_1001');
      expect(mockHttp.lastRequest?.url.path, '/message');
      expect(mockHttp.lastRequest?.headers['authorization'], startsWith('Basic '));

      final decoded = jsonDecode(mockHttp.lastRequestBody!) as Map<String, dynamic>;
      expect(decoded['phoneNumbers'], contains('03001234567'));
      expect(decoded['message'], 'Hello Student Arrived');
    });

    test('fails gracefully when gateway URL is missing', () async {
      final res = await gateway.sendSms(
        to: '03001234567',
        message: 'Test',
        credentials: {},
      );

      expect(res.success, isFalse);
      expect(res.error, contains('not configured'));
    });

    test('handles HTTP 500 error gracefully', () async {
      mockHttp.statusCode = 500;
      mockHttp.responseBody = 'SIM Card Not Ready';

      final res = await gateway.sendSms(
        to: '03001234567',
        message: 'Test',
        credentials: {'sms_gateway_url': 'http://192.168.18.50:8080'},
      );

      expect(res.success, isFalse);
      expect(res.error, contains('HTTP 500'));
    });
  });

  group('SmsQueueDispatcher', () {
    test('does not process queue when sms_enabled is false', () async {
      await db.settingsDao.setSetting('sms_enabled', 'false');
      await db.settingsDao.setSetting('sms_gateway_url', 'http://192.168.18.50:8080');

      await db.notificationsDao.createJob(
        studentId: 101,
        date: '2026-10-02',
        channel: 'sms',
        recipientPhone: '03001234567',
        message: 'Student checkin test',
      );

      await dispatcher.processPendingQueue();

      final pending = await db.notificationsDao.getNotificationHistory(channel: 'sms', status: 'pending');
      expect(pending.length, 1);
    });

    test('sequentially processes pending jobs when sms_enabled is true', () async {
      await db.settingsDao.setSetting('sms_enabled', 'true');
      await db.settingsDao.setSetting('sms_provider', 'android_gateway');
      await db.settingsDao.setSetting('sms_gateway_url', 'http://192.168.18.50:8080');
      await db.settingsDao.setSetting('sms_throttle_delay_sec', '0.01'); // fast test delay

      final jobId = await db.notificationsDao.createJob(
        studentId: 102,
        date: '2026-10-02',
        channel: 'sms',
        recipientPhone: '03009876543',
        message: 'Your child Ali arrived at school',
      );

      await dispatcher.processPendingQueue();

      final sent = await db.notificationsDao.getNotificationHistory(channel: 'sms', status: 'sent');
      expect(sent.length, 1);
      expect(sent.first.id, jobId);
      expect(sent.first.status, 'sent');
    });

    test('marks job as failed and records attempt on network failure', () async {
      mockHttp.statusCode = 503;
      mockHttp.responseBody = 'Service Unavailable';

      await db.settingsDao.setSetting('sms_enabled', 'true');
      await db.settingsDao.setSetting('sms_provider', 'android_gateway');
      await db.settingsDao.setSetting('sms_gateway_url', 'http://192.168.18.50:8080');
      await db.settingsDao.setSetting('sms_throttle_delay_sec', '0.01');

      final jobId = await db.notificationsDao.createJob(
        studentId: 103,
        date: '2026-10-02',
        channel: 'sms',
        recipientPhone: '03001112233',
        message: 'Failure test',
      );

      await dispatcher.processPendingQueue();

      final failed = await db.notificationsDao.getNotificationHistory(channel: 'sms', status: 'failed');
      expect(failed.length, 1);
      expect(failed.first.id, jobId);
      expect(failed.first.status, 'failed');
    });
  });
}
