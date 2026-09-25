import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/attendance_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../utils/date_formatter.dart';
import 'status_badge.dart';

class IndividualAttendanceDialog extends ConsumerWidget {
  const IndividualAttendanceDialog({
    super.key,
    required this.personType, // 'student' or 'staff'
    required this.personId,
    required this.personCode,
    required this.personName,
    this.subtitle,
  });

  final String personType;
  final int personId;
  final String personCode;
  final String personName;
  final String? subtitle;

  static void show(
    BuildContext context, {
    required String personType,
    required int personId,
    required String personCode,
    required String personName,
    String? subtitle,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => IndividualAttendanceDialog(
        personType: personType,
        personId: personId,
        personCode: personCode,
        personName: personName,
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final historyFuture = db.attendanceDao.getAttendanceHistoryForPerson(
      personType: personType,
      studentId: personType == 'student' ? personId : null,
      staffId: personType == 'staff' ? personId : null,
    );

    final initials = personName.split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join();

    return AlertDialog(
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary,
            child: Text(
              initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  personName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  '$personCode • ${subtitle ?? (personType == 'student' ? 'Student' : 'Staff')}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: FutureBuilder<List<AttendanceRecordView>>(
          future: historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error loading history: ${snapshot.error}'));
            }

            final records = snapshot.data ?? [];

            // Compute summary metrics
            final total = records.length;
            final present = records.where((r) => r.status == 'present').length;
            final late = records.where((r) => r.status == 'late').length;
            final absent = records.where((r) => r.status == 'absent').length;
            final rate = total > 0 ? (((present + late) / total) * 100).toStringAsFixed(1) : '100.0';

            return Column(
              children: [
                // Top Metric Cards Row
                Row(
                  children: [
                    _buildStatCard('Total Logged', '$total days', AppColors.primary),
                    const SizedBox(width: 10),
                    _buildStatCard('Present', '$present days', AppColors.present),
                    const SizedBox(width: 10),
                    _buildStatCard('Late Arrival', '$late days', AppColors.late),
                    const SizedBox(width: 10),
                    _buildStatCard('Absences', '$absent days', AppColors.absent),
                    const SizedBox(width: 10),
                    _buildStatCard('Attendance Rate', '$rate%', AppColors.secondary),
                  ],
                ),
                const SizedBox(height: 16),

                // Historical Records Table
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: records.isEmpty
                        ? const Center(
                            child: Text(
                              'No historical attendance punches recorded yet.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: records.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                            itemBuilder: (ctx, index) {
                              final r = records[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    // Date
                                    SizedBox(
                                      width: 110,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today, size: 13, color: AppColors.textSecondary),
                                          const SizedBox(width: 6),
                                          Text(
                                            r.date,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Check-in Time
                                    SizedBox(
                                      width: 130,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.login, size: 14, color: AppColors.present),
                                          const SizedBox(width: 4),
                                          Text(
                                            r.checkInTime != null
                                                ? DateFormatter.formatEpochTime(r.checkInTime)
                                                : '—',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Check-out Time
                                    SizedBox(
                                      width: 130,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.logout, size: 14, color: AppColors.late),
                                          const SizedBox(width: 4),
                                          Text(
                                            r.checkOutTime != null
                                                ? DateFormatter.formatEpochTime(r.checkOutTime)
                                                : '—',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Status Badge
                                    SizedBox(
                                      width: 90,
                                      child: StatusBadge(status: r.status),
                                    ),
                                    // Method Badge
                                    SizedBox(
                                      width: 110,
                                      child: Row(
                                        children: [
                                          Icon(
                                            r.method == 'fingerprint'
                                                ? Icons.fingerprint
                                                : (r.method == 'manual' ? Icons.edit_note : Icons.pin),
                                            size: 14,
                                            color: AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            r.method.toUpperCase(),
                                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Notes
                                    Expanded(
                                      child: Text(
                                        r.notes ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
