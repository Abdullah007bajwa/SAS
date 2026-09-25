import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:school_attendance_portal/core/database/app_database.dart';
import 'package:school_attendance_portal/core/database/database_provider.dart';
import 'package:school_attendance_portal/core/database/demo_seeder.dart';
import 'package:school_attendance_portal/core/hardware/hardware_providers.dart';
import 'package:school_attendance_portal/core/theme/app_theme.dart';
import 'package:school_attendance_portal/features/dashboard/dashboard_screen.dart';
import '../test_helper.dart';

void main() {
  setupSqliteForTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    await DemoSeeder.seed(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestableWidget(Widget child) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  group('DashboardScreen Widget Tests', () {
    testWidgets('Dashboard renders metric cards with seeded data', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(buildTestableWidget(const DashboardScreen()));
      await tester.pumpAndSettle();

      // Verify dashboard title and metric cards
      expect(find.text('School Attendance Overview'), findsOneWidget);
      expect(find.text('Total Enrolled'), findsOneWidget);
      expect(find.text('Students Present'), findsOneWidget);
      expect(find.text('Late Arrivals'), findsOneWidget);
      expect(find.text('Students Absent'), findsOneWidget);
      expect(find.text('Total Staff'), findsOneWidget);
      expect(find.text('Staff On Duty'), findsOneWidget);
      expect(find.text('Staff Late'), findsOneWidget);

      // Verify Quick Action button
      expect(find.text('Run Cutoff Check Now'), findsOneWidget);
    });
  });
}
