import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:school_attendance_portal/core/database/app_database.dart';
import 'package:school_attendance_portal/core/database/demo_seeder.dart';
import 'package:school_attendance_portal/core/hardware/k50_device_user_map.dart';
import 'package:school_attendance_portal/core/hardware/school_attendance_processor.dart';
import 'package:school_attendance_portal/core/hardware/zk_attendance_dedup.dart';
import 'package:school_attendance_portal/core/hardware/zk_backend_client.dart';
import 'package:school_attendance_portal/core/notifications/absence_cutoff_service.dart';
import 'package:school_attendance_portal/core/notifications/notification_provider.dart';
import '../test_helper.dart';

class MockNotificationProvider implements NotificationProvider {
  @override
  String get name => 'mock_provider';

  int smsSent = 0;
  int whatsappSent = 0;

  @override
  Future<NotificationSendResult> sendSms({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    smsSent++;
    return const NotificationSendResult(success: true, messageId: 'SMS_MOCK_123');
  }

  @override
  Future<NotificationSendResult> sendWhatsApp({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    whatsappSent++;
    return const NotificationSendResult(success: true, messageId: 'WA_MOCK_123');
  }
}

void main() {
  setupSqliteForTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;
  late MockNotificationProvider notificationProvider;
  late AbsenceCutoffService cutoffService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    await DemoSeeder.seed(db);

    final dedup = ZkAttendanceDedup(prefs);
    final userMap = K50DeviceUserMap(prefs);
    final processor = SchoolAttendanceProcessor(
      db: db,
      backendClient: ZkBackendClient(baseUrl: 'http://127.0.0.1:8787'),
      dedup: dedup,
      deviceUserMap: userMap,
    );

    notificationProvider = MockNotificationProvider();

    cutoffService = AbsenceCutoffService(
      db: db,
      attendanceProcessor: processor,
      notificationProvider: notificationProvider,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('AbsenceCutoffService Tests', () {
    test('evaluateCutoffAndNotify detects absent students and triggers alerts', () async {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));

      // Evaluate cutoff for tomorrow where no students have scanned yet
      final result = await cutoffService.evaluateCutoffAndNotify(date: tomorrow);

      expect(result.totalEnrolled, greaterThanOrEqualTo(16));
      expect(result.absencesDetected, equals(result.totalEnrolled));
      expect(result.smsJobsCreated, greaterThan(0));
      expect(result.whatsappJobsCreated, greaterThan(0));
      expect(notificationProvider.smsSent, equals(result.smsJobsCreated));
      expect(notificationProvider.whatsappSent, equals(result.whatsappJobsCreated));
    });
  });
}
