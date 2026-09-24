import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/attendance_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/notifications/notification_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/metric_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../../utils/date_formatter.dart';

final dashboardStatsProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final today = db.attendanceDao.todayDateString();

  final totalStudents = await db.studentsDao.countActiveStudents();
  final totalStaff = await db.staffDao.countActiveStaff();

  final studentsPresent = await db.attendanceDao.countPresentToday('student', today);
  final studentsLate = await db.attendanceDao.countLateToday('student', today);
  final studentsAbsent = await db.attendanceDao.countAbsentToday('student', today);

  final staffPresent = await db.attendanceDao.countPresentToday('staff', today);
  final staffLate = await db.attendanceDao.countLateToday('staff', today);

  final recentPunches = await db.attendanceDao.getRecentPunchStream(limit: 10);

  return {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'School Attendance Overview',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Real-time biometric monitoring and attendance statistics',
                        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.send_and_archive, size: 16),
                    label: const Text('Run Cutoff Check Now'),
                    onPressed: () async {
                      final cutoffService = ref.read(absenceCutoffServiceProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Evaluating absences & dispatching parent alerts...')),
                      );
                      final res = await cutoffService.evaluateCutoffAndNotify();
                      ref.invalidate(dashboardStatsProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Cutoff finished: ${res.absencesDetected} absent. Created ${res.smsJobsCreated} SMS & ${res.whatsappJobsCreated} WhatsApp alerts.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Student Metrics
              const Text(
                'STUDENT ATTENDANCE',
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
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Late Arrivals',
                      value: '$studentsLate',
                      icon: Icons.access_time,
                      color: AppColors.late,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Students Absent',
                      value: '$studentsAbsent',
                      icon: Icons.cancel_outlined,
                      color: AppColors.absent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Staff Metrics
              const Text(
                'TEACHERS & STAFF ATTENDANCE',
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
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: MetricCard(
                      title: 'Staff Late',
                      value: '$staffLate',
                      icon: Icons.timer_outlined,
                      color: AppColors.late,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Live Punch Feed Table
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
                          TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Refresh'),
                            onPressed: () => ref.invalidate(dashboardStatsProvider),
                          ),
                        ],
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
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2),
                            1: FlexColumnWidth(1.2),
                            2: FlexColumnWidth(1.5),
                            3: FlexColumnWidth(1.5),
                            4: FlexColumnWidth(1),
                            5: FlexColumnWidth(1),
                          },
                          children: [
                            const TableRow(
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
                              ),
                              children: [
                                Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                                Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('ROLE / TYPE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                                Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('ID / CODE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                                Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('PUNCH TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                                Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                                Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('METHOD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                              ],
                            ),
                            ...recentPunches.map((p) => TableRow(
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: AppColors.border)),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(p.personName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    p.personType == 'student'
                                        ? '${p.className ?? "Student"} ${p.sectionName != null ? "- ${p.sectionName}" : ""}'
                                        : (p.staffCategory?.toUpperCase() ?? 'STAFF'),
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(p.personCode, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(DateFormatter.formatEpochTime(p.checkInTime)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: StatusBadge(status: p.status),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(p.method.toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                ),
                              ],
                            )),
                          ],
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
