import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/attendance/attendance_screen.dart';
import '../../features/classes/classes_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/notifications/notification_history_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/staff/staff_screen.dart';
import '../../features/students/students_screen.dart';
import '../../shared/layout/main_layout.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainLayout(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/attendance',
          builder: (context, state) => const AttendanceScreen(),
        ),
        GoRoute(
          path: '/students',
          builder: (context, state) => const StudentsScreen(),
        ),
        GoRoute(
          path: '/classes',
          builder: (context, state) => const ClassesScreen(),
        ),
        GoRoute(
          path: '/staff',
          builder: (context, state) => const StaffScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationHistoryScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
  ],
);
