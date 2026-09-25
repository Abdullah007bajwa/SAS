import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/daos/attendance_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/hardware/hardware_providers.dart';
import '../../core/hardware/zk_device_service.dart';
import '../../core/notifications/notification_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/individual_attendance_dialog.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../../utils/date_formatter.dart';
import '../attendance/attendance_screen.dart';

final dashboardDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final dashboardStatsProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final selectedDate = ref.watch(dashboardDateProvider);
  final dateStr = DateFormatter.toIsoDateString(selectedDate);

  final totalStudents = await db.studentsDao.countActiveStudents();
  final totalStaff = await db.staffDao.countActiveStaff();

  final studentsPresent = await db.attendanceDao.countPresentToday('student', dateStr);
  final studentsLate = await db.attendanceDao.countLateToday('student', dateStr);
  final studentsAbsent = await db.attendanceDao.countAbsentToday('student', dateStr);

  final staffPresent = await db.attendanceDao.countPresentToday('staff', dateStr);
  final staffLate = await db.attendanceDao.countLateToday('staff', dateStr);

  final recentPunches = await db.attendanceDao.getRecentPunchStream(limit: 15);

  return {
    'selectedDate': selectedDate,
    'dateStr': dateStr,
    'totalStudents': totalStudents,
    'totalStaff': totalStaff,
    'studentsPresent': studentsPresent,
    'studentsLate': studentsLate,
    'studentsAbsent': studentsAbsent,
    'staffPresent': staffPresent,
    'staffLate': staffLate,
    'recentPunches': recentPunches,
  };
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _navigateToFilteredAttendance(
    BuildContext context,
    WidgetRef ref, {
    required String role,
    String? status,
  }) {
    ref.read(attendanceFilterRoleProvider.notifier).state = role;
    ref.read(attendanceFilterStatusProvider.notifier).state = status ?? 'all';
    final selectedDate = ref.read(dashboardDateProvider);
    ref.read(attendanceFilterDateProvider.notifier).state = selectedDate;
    context.go('/attendance');
  }

  void _showQuickPunchModal(BuildContext context, WidgetRef ref) {
    final codeCtrl = TextEditingController(text: '1001');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fingerprint, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Simulate K50 Biometric Punch', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a numeric device user ID to simulate an immediate optical sensor scan from the K50 reader:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Device User ID (e.g. 1001 for Student, 8001 for Teacher)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '• Range 1001-7999: Mapped to Students\n• Range 8001-8999: Mapped to Teachers / Staff',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Record Punch Now'),
            onPressed: () async {
              final id = codeCtrl.text.trim();
              if (id.isEmpty) return;
              Navigator.pop(ctx);

              final processor = ref.read(schoolAttendanceProcessorProvider);
              await processor.applyLogs([
                LogEntry(
                  userId: id,
                  deviceUserId: id,
                  timestamp: DateTime.now(),
                  verifyType: 1, // fingerprint
                ),
              ]);

              ref.invalidate(dashboardStatsProvider);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Punch successfully processed for ID $id!'),
                    backgroundColor: AppColors.present,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final selectedDate = ref.watch(dashboardDateProvider);
    final isToday = DateFormatter.toIsoDateString(selectedDate) ==
        DateFormatter.toIsoDateString(DateTime.now());

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading dashboard: $e')),
      data: (stats) {
        final totalStudents = stats['totalStudents'] as int;
        final totalStaff = stats['totalStaff'] as int;
        final studentsPresent = stats['studentsPresent'] as int;
        final studentsLate = stats['studentsLate'] as int;
        final studentsAbsent = stats['studentsAbsent'] as int;
        final staffPresent = stats['staffPresent'] as int;
        final staffLate = stats['staffLate'] as int;
        final recentPunches = stats['recentPunches'] as List<AttendanceRecordView>;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Quick Action Row
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          const Text(
                            'School Attendance Overview',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          // Interactive Date Badge
                          ActionChip(
                            avatar: const Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                            label: Text(
                              isToday ? 'Today, ${DateFormatter.formatDate(selectedDate)}' : DateFormatter.formatDate(selectedDate),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.primary),
                            ),
                            backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                            side: const BorderSide(color: AppColors.primary, width: 0.8),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2027),
                              );
                              if (picked != null) {
                                ref.read(dashboardDateProvider.notifier).state = picked;
                              }
                            },
                          ),
                          if (!isToday) ...[
                            IconButton(
                              tooltip: 'Reset to Today',
                              icon: const Icon(Icons.replay, size: 16, color: AppColors.textSecondary),
                              onPressed: () {
                                ref.read(dashboardDateProvider.notifier).state = DateTime.now();
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Interactive biometric attendance metrics, real-time scan stream, and quick drill-downs',
                        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.fingerprint, size: 16),
                        label: const Text('Test Scan'),
                        onPressed: () => _showQuickPunchModal(context, ref),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send_and_archive, size: 16),
                        label: const Text('Run Cutoff Check Now'),
                        onPressed: () async {
                          final cutoffService = ref.read(absenceCutoffServiceProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Evaluating absences & dispatching parent alerts...')),
                          );
                          final res = await cutoffService.evaluateCutoffAndNotify(date: selectedDate);
                          ref.invalidate(dashboardStatsProvider);
                          if (context.mounted) {
                            if (res.isOffDay) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Selected date is an off-day (Sunday/Holiday). Cutoff skipped.'),
                                  backgroundColor: AppColors.late,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Cutoff finished: ${res.absencesDetected} absent. Created ${res.smsJobsCreated} SMS & ${res.whatsappJobsCreated} WhatsApp alerts.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Student Metrics
              const Text(
                'STUDENT ATTENDANCE (CLICK CARD TO FILTER)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      title: 'Total Enrolled',
                      value: '$totalStudents',
                      icon: Icons.school,
                      color: AppColors.primary,
                      tooltip: 'Click to open Students directory',
                      onTap: () => context.go('/students'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Students Present',
                      value: '$studentsPresent',
                      subtitle: '$studentsLate arrived late',
                      icon: Icons.check_circle_outline,
                      color: AppColors.present,
                      tooltip: 'Click to view present students',
                      onTap: () => _navigateToFilteredAttendance(context, ref, role: 'student', status: 'present'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Late Arrivals',
                      value: '$studentsLate',
                      icon: Icons.access_time,
                      color: AppColors.late,
                      tooltip: 'Click to view late arrivals',
                      onTap: () => _navigateToFilteredAttendance(context, ref, role: 'student', status: 'late'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Students Absent',
                      value: '$studentsAbsent',
                      icon: Icons.cancel_outlined,
                      color: AppColors.absent,
                      tooltip: 'Click to view absent students',
                      onTap: () => _navigateToFilteredAttendance(context, ref, role: 'student', status: 'absent'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Staff Metrics
              const Text(
                'TEACHERS & STAFF ATTENDANCE (CLICK CARD TO FILTER)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      title: 'Total Staff',
                      value: '$totalStaff',
                      icon: Icons.badge,
                      color: AppColors.secondary,
                      tooltip: 'Click to open Staff directory',
                      onTap: () => context.go('/staff'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Staff On Duty',
                      value: '$staffPresent',
                      subtitle: '$staffLate after grace period',
                      icon: Icons.verified_user_outlined,
                      color: AppColors.present,
                      tooltip: 'Click to view on-duty staff',
                      onTap: () => _navigateToFilteredAttendance(context, ref, role: 'staff', status: 'present'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Staff Late',
                      value: '$staffLate',
                      icon: Icons.timer_outlined,
                      color: AppColors.late,
                      tooltip: 'Click to view late staff',
                      onTap: () => _navigateToFilteredAttendance(context, ref, role: 'staff', status: 'late'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Live Punch Feed Table (Interactive Rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.sensors, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Live Biometric Scan Stream (K50)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.list_alt, size: 16),
                                label: const Text('View All in Attendance'),
                                onPressed: () => context.go('/attendance'),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 18),
                                tooltip: 'Refresh stream',
                                onPressed: () => ref.invalidate(dashboardStatsProvider),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Click any punch row below to view individual attendance history:',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 16),
                      if (recentPunches.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No biometric punches recorded yet today. Scans from the K50 device will appear here instantly.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recentPunches.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (ctx, index) {
                            final p = recentPunches[index];
                            final personId = p.personType == 'student'
                                ? (p.studentId ?? 0)
                                : (p.staffId ?? 0);

                            return InkWell(
                              onTap: () {
                                IndividualAttendanceDialog.show(
                                  context,
                                  personType: p.personType,
                                  personId: personId,
                                  personCode: p.personCode,
                                  personName: p.personName,
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                child: Row(
                                  children: [
                                    // Avatar / Icon
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: p.personType == 'student'
                                          ? AppColors.primary.withValues(alpha: 0.1)
                                          : AppColors.secondary.withValues(alpha: 0.1),
                                      child: Icon(
                                        p.personType == 'student' ? Icons.school : Icons.badge,
                                        size: 16,
                                        color: p.personType == 'student' ? AppColors.primary : AppColors.secondary,
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Name & Role
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.personName,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          Text(
                                            p.personType == 'student'
                                                ? '${p.className ?? "Student"} ${p.sectionName != null ? "- ${p.sectionName}" : ""}'
                                                : (p.staffCategory?.toUpperCase() ?? 'STAFF'),
                                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Code
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        p.personCode,
                                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textSecondary),
                                      ),
                                    ),

                                    // Time
                                    Expanded(
                                      flex: 1,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.access_time, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 4),
                                          Text(
                                            DateFormatter.formatEpochTime(p.checkInTime),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Status Badge
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: StatusBadge(status: p.status),
                                    ),

                                    // Method Chip
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        p.method.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Action Icon
                                    const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
