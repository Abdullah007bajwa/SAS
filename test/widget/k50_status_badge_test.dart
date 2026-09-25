import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_attendance_portal/core/hardware/k50_status_provider.dart';
import 'package:school_attendance_portal/core/hardware/zk_backend_client.dart';
import 'package:school_attendance_portal/core/theme/app_theme.dart';
import 'package:school_attendance_portal/shared/widgets/k50_status_badge.dart';
import '../test_helper.dart';

class MockZkBackendClient extends ZkBackendClient {
  MockZkBackendClient() : super(baseUrl: 'http://127.0.0.1:8787');

  @override
  Future<BackendHealthResponse> health() async {
    return const BackendHealthResponse(ok: false, error: 'Bridge offline in test');
  }
}

void main() {
  setupSqliteForTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('K50StatusBadge displays offline badge and opens diagnostic dialog on click', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));

    final mockClient = MockZkBackendClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          k50StatusProvider.overrideWith((ref) => K50StatusNotifier(mockClient)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: K50StatusBadge()),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify K50 Disconnected badge exists
    expect(find.text('K50 Disconnected'), findsOneWidget);

    // Tap the badge
    await tester.tap(find.text('K50 Disconnected'));
    await tester.pumpAndSettle();

    // Verify diagnostic modal opened
    expect(find.text('K50 Biometric Status'), findsOneWidget);
    expect(find.text('Probe Again'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Tap Close to dismiss
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('K50 Biometric Status'), findsNothing);
  });
}
