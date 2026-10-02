import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/database/database_provider.dart';
import 'core/hardware/hardware_providers.dart';
import 'core/notifications/notification_providers.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_providers.dart';
import 'core/theme/app_theme.dart';

class SchoolAttendanceApp extends ConsumerStatefulWidget {
  const SchoolAttendanceApp({super.key});

  @override
  ConsumerState<SchoolAttendanceApp> createState() => _SchoolAttendanceAppState();
}

class _SchoolAttendanceAppState extends ConsumerState<SchoolAttendanceApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundServices();
    });
  }

  Future<void> _startBackgroundServices() async {
    final db = ref.read(appDatabaseProvider);
    final processor = ref.read(schoolAttendanceProcessorProvider);
    final cutoffTimer = ref.read(dailyCutoffTimerProvider);
    final syncService = ref.read(syncServiceProvider);
    final bridgeLauncher = ref.read(k50BridgeLauncherProvider);

    final deviceIp = await db.settingsDao.getSetting('k50_ip', defaultValue: '192.168.18.78');
    final devicePortStr = await db.settingsDao.getSetting('k50_port', defaultValue: '4370');
    final devicePort = int.tryParse(devicePortStr) ?? 4370;
    final bridgePort = await db.settingsDao.getSetting('k50_bridge_port', defaultValue: '8787');
    final bridgeUrl = 'http://127.0.0.1:$bridgePort';

    // 1. Auto-launch C# K50 bridge on Windows PC
    if (Platform.isWindows) {
      bridgeLauncher.ensureRunning(
        bridgeUrls: [bridgeUrl],
        deviceIp: deviceIp,
        devicePort: devicePort,
      );
    }

    // 2. Start biometric attendance listener (WebSocket push + periodic fallback poll)
    final smsDispatcher = ref.read(smsQueueDispatcherProvider);
    processor.setSmsDispatcher(smsDispatcher);
    processor.start(bridgeUrl);

    // 3. Start automated daily cutoff absence notification monitor
    cutoffTimer.start();

    // 4. Start sequential carrier-safe SMS queue dispatcher
    smsDispatcher.start();

    // 5. Start periodic cloud synchronization
    syncService.startPeriodicSync();

    // 6. Automated crash protection daily database backup
    final backupService = ref.read(databaseBackupServiceProvider);
    backupService.autoDailyBackup(db);
  }

  @override
  void dispose() {
    ref.read(schoolAttendanceProcessorProvider).stop();
    ref.read(dailyCutoffTimerProvider).stop();
    ref.read(smsQueueDispatcherProvider).stop();
    ref.read(syncServiceProvider).stopPeriodicSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'School Attendance Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}
