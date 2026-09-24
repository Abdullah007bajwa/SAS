import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/notifications_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/notifications/notification_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/status_badge.dart';
import '../../utils/date_formatter.dart';

final notificationFilterDateProvider = StateProvider<DateTime>((ref) => DateTime.now());
final notificationFilterChannelProvider = StateProvider<String>((ref) => 'all');

final notificationHistoryProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final date = ref.watch(notificationFilterDateProvider);
  final channel = ref.watch(notificationFilterChannelProvider);

  final dateStr = DateFormatter.toIsoDateString(date);

  return db.notificationsDao.getNotificationHistory(
    date: dateStr,
    channel: channel == 'all' ? null : channel,
  );
});

class NotificationHistoryScreen extends ConsumerWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(notificationFilterDateProvider);
    final selectedChannel = ref.watch(notificationFilterChannelProvider);
    final historyAsync = ref.watch(notificationHistoryProvider);

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
                  'Parent Absence Alerts & Notification Queue',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Audit trail of automated SMS and WhatsApp absence alerts sent to parents',
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
                      ref.read(notificationFilterDateProvider.notifier).state = picked;
                    }
                  },
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Evaluate & Send Alerts Now'),
                  onPressed: () async {
                    final cutoffService = ref.read(absenceCutoffServiceProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Evaluating absences and creating idempotent parent alerts...')),
                    );
                    final res = await cutoffService.evaluateCutoffAndNotify(date: date);
                    ref.invalidate(notificationHistoryProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Completed: ${res.absencesDetected} absences found, ${res.smsJobsCreated} SMS & ${res.whatsappJobsCreated} WhatsApp jobs dispatched.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Filter Bar
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Channel: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                DropdownButton<String>(
                  value: selectedChannel,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Channels')),
                    DropdownMenuItem(value: 'sms', child: Text('SMS Only')),
                    DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp Only')),
                  ],
                  onChanged: (val) {
                    if (val != null) ref.read(notificationFilterChannelProvider.notifier).state = val;
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Notifications',
                  onPressed: () => ref.invalidate(notificationHistoryProvider),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // History Table
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: historyAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading alerts: $e')),
                data: (jobs) {
                  if (jobs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No parent absence notification jobs for this date and channel.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.8),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(1.4),
                        4: FlexColumnWidth(3),
                        5: FlexColumnWidth(1.2),
                        6: FlexColumnWidth(1),
                      },
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
                          ),
                          children: [
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STUDENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CLASS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CHANNEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('RECIPIENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('MESSAGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('SENT AT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                          ],
                        ),
                        ...jobs.map((j) => TableRow(
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border)),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(j.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(j.className ?? '—', style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    j.channel == 'whatsapp' ? Icons.chat : Icons.sms,
                                    size: 14,
                                    color: j.channel == 'whatsapp' ? AppColors.present : AppColors.primaryLight,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(j.channel.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(j.recipientPhone, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                j.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(DateFormatter.formatEpochTime(j.sentAt ?? j.scheduledAt), style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: StatusBadge(status: j.status),
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
}
