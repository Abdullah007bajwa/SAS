import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/attendance_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/status_badge.dart';
import '../../utils/date_formatter.dart';

final attendanceFilterDateProvider = StateProvider<DateTime>((ref) => DateTime.now());
final attendanceFilterRoleProvider = StateProvider<String>((ref) => 'all'); // all, student, staff
final attendanceFilterClassProvider = StateProvider<int?>((ref) => null);
final attendanceFilterStatusProvider = StateProvider<String>((ref) => 'all'); // all, present, late, absent

final attendanceListProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final date = ref.watch(attendanceFilterDateProvider);
  final role = ref.watch(attendanceFilterRoleProvider);
  final classId = ref.watch(attendanceFilterClassProvider);
  final status = ref.watch(attendanceFilterStatusProvider);

  final dateStr = DateFormatter.toIsoDateString(date);

  return db.attendanceDao.queryAttendances(
    date: dateStr,
    personType: role,
    classId: classId,
    status: status,
  );
});

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(attendanceFilterDateProvider);
    final selectedRole = ref.watch(attendanceFilterRoleProvider);
    final selectedStatus = ref.watch(attendanceFilterStatusProvider);
    final recordsAsync = ref.watch(attendanceListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unified Attendance Portal',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Daily attendance records for students, teachers, and school staff',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: Text(DateFormatter.formatDate(date)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      ref.read(attendanceFilterDateProvider.notifier).state = picked;
                    }
                  },
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Manual Entry'),
                  onPressed: () => _showManualEntryDialog(context, ref),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Filter Bar
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('Role: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                DropdownButton<String>(
                  value: selectedRole,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Roles')),
                    DropdownMenuItem(value: 'student', child: Text('Students Only')),
                    DropdownMenuItem(value: 'staff', child: Text('Staff / Teachers')),
                  ],
                  onChanged: (val) {
                    if (val != null) ref.read(attendanceFilterRoleProvider.notifier).state = val;
                  },
                ),
                const SizedBox(width: 24),
                const Text('Status: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                DropdownButton<String>(
                  value: selectedStatus,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    DropdownMenuItem(value: 'present', child: Text('Present')),
                    DropdownMenuItem(value: 'late', child: Text('Late')),
                    DropdownMenuItem(value: 'absent', child: Text('Absent')),
                  ],
                  onChanged: (val) {
                    if (val != null) ref.read(attendanceFilterStatusProvider.notifier).state = val;
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Attendance',
                  onPressed: () => ref.invalidate(attendanceListProvider),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Records Table
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: recordsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading attendance records: $e')),
                data: (records) {
                  if (records.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy, size: 48, color: AppColors.textMuted.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          const Text(
                            'No attendance records found for this date and filter criteria.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.5),
                        3: FlexColumnWidth(1.2),
                        4: FlexColumnWidth(1.2),
                        5: FlexColumnWidth(1),
                        6: FlexColumnWidth(1),
                      },
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
                          ),
                          children: [
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('ID / CODE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CLASS / CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CHECK-IN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CHECK-OUT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('METHOD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                          ],
                        ),
                        ...records.map((r) => TableRow(
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border)),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(r.personName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(r.personCode, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                r.personType == 'student'
                                    ? '${r.className ?? ""} ${r.sectionName != null ? "- ${r.sectionName}" : ""}'
                                    : (r.staffCategory?.toUpperCase() ?? 'STAFF'),
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(DateFormatter.formatEpochTime(r.checkInTime)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(DateFormatter.formatEpochTime(r.checkOutTime)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: StatusBadge(status: r.status),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(r.method.toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            ),
                          ],
                        )),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showManualEntryDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Manual Attendance'),
        content: const Text(
          'Biometric scans from the K50 are captured automatically.\n\nUse this action to mark an excused presence or manual punch if a student or teacher forgot their badge or scanned off-device.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
