import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  void _startBackgroundServices() {
    final processor = ref.read(schoolAttendanceProcessorProvider);
    final cutoffTimer = ref.read(dailyCutoffTimerProvider);
    final syncService = ref.read(syncServiceProvider);
    final bridgeLauncher = ref.read(k50BridgeLauncherProvider);

    // 1. Auto-launch C# K50 bridge on Windows PC
    if (Platform.isWindows) {
      bridgeLauncher.ensureRunning(bridgeUrls: ['http://127.0.0.1:8787']);
    }

    // 2. Start biometric attendance listener (WebSocket push + periodic fallback poll)
    processor.start('http://127.0.0.1:8787');

    // 3. Start automated daily cutoff absence notification monitor
    cutoffTimer.start();

    // 4. Start periodic cloud synchronization
    syncService.startPeriodicSync();
  }

  @override
  void dispose() {
    ref.read(schoolAttendanceProcessorProvider).stop();
    ref.read(dailyCutoffTimerProvider).stop();
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
