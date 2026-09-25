import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sync/sync_providers.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../utils/date_formatter.dart';
import '../widgets/k50_status_badge.dart';

class MainLayout extends ConsumerWidget {
  const MainLayout({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final currentRoute = GoRouterState.of(context).uri.toString();

    return Scaffold(
      body: Row(
        children: [
          // Sidebar Navigation
          Container(
            width: 250,
            color: AppColors.primaryDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branding Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.school, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SAS Portal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'School Attendance',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF1E293B), height: 1),
                const SizedBox(height: 16),

                // Navigation Items
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  title: 'Dashboard',
                  route: '/',
                  isSelected: currentRoute == '/',
                ),
                _NavItem(
                  icon: Icons.fingerprint,
                  activeIcon: Icons.fingerprint,
                  title: 'Unified Attendance',
                  route: '/attendance',
                  isSelected: currentRoute == '/attendance',
                ),
                _NavItem(
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  title: 'Students & Rosters',
                  route: '/students',
                  isSelected: currentRoute == '/students',
                ),
                _NavItem(
                  icon: Icons.class_outlined,
                  activeIcon: Icons.class_,
                  title: 'Classes & Sections',
                  route: '/classes',
                  isSelected: currentRoute == '/classes',
                ),
                _NavItem(
                  icon: Icons.badge_outlined,
                  activeIcon: Icons.badge,
                  title: 'Staff & Teachers',
                  route: '/staff',
                  isSelected: currentRoute == '/staff',
                ),
                _NavItem(
                  icon: Icons.notifications_none,
                  activeIcon: Icons.notifications,
                  title: 'Parent Alerts',
                  route: '/notifications',
                  isSelected: currentRoute == '/notifications',
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  title: 'Settings',
                  route: '/settings',
                  isSelected: currentRoute == '/settings',
                ),

                const Spacer(),
                const Divider(color: Color(0xFF1E293B), height: 1),

                // Cloud Sync Indicator
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        syncStatus == SyncStatus.syncing
                            ? Icons.sync
                            : (syncStatus == SyncStatus.success
                                ? Icons.cloud_done
                                : Icons.cloud_outlined),
                        size: 18,
                        color: syncStatus == SyncStatus.syncing
                            ? AppColors.late
                            : (syncStatus == SyncStatus.success ? AppColors.present : AppColors.textMuted),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          syncStatus == SyncStatus.syncing
                              ? 'Syncing...'
                              : (syncStatus == SyncStatus.success ? 'Cloud Synced' : 'Sync Idle'),
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                        tooltip: 'Sync Now',
                        onPressed: () => ref.read(syncServiceProvider).syncNow(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main View Content
          Expanded(
            child: Column(
              children: [
                // Top App Bar
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormatter.formatDate(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          const K50StatusBadge(),
                          const SizedBox(width: 16),
                          CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: const Text('AD', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Content View
                Expanded(
                  child: Container(
                    color: AppColors.background,
                    padding: const EdgeInsets.all(28),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.route,
    required this.isSelected,
  });

  final IconData icon;
  final IconData activeIcon;
  final String title;
  final String route;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        onTap: () => context.go(route),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? Colors.white : AppColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
