import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/staff_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/hardware/hardware_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/status_badge.dart';
import '../../utils/id_generator.dart';

final staffCategoryFilterProvider = StateProvider<String>((ref) => 'all');

final staffListProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final cat = ref.watch(staffCategoryFilterProvider);
  return db.staffDao.getAllStaff(category: cat == 'all' ? null : cat);
});

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);
    final selectedCat = ref.watch(staffCategoryFilterProvider);

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
                  'Teachers & School Staff',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage faculty, staff roles, expected shift start times, and grace periods',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Add Staff Member'),
              onPressed: () => _showAddStaffDialog(context, ref),
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
                const Text('Category: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                DropdownButton<String>(
                  value: selectedCat,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Categories')),
                    DropdownMenuItem(value: 'teacher', child: Text('Teachers')),
                    DropdownMenuItem(value: 'administrator', child: Text('Administrators')),
                    DropdownMenuItem(value: 'support_staff', child: Text('Support Staff')),
                  ],
                  onChanged: (val) {
                    if (val != null) ref.read(staffCategoryFilterProvider.notifier).state = val;
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Staff',
                  onPressed: () => ref.invalidate(staffListProvider),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Staff Table
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: staffAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading staff: $e')),
                data: (staffList) {
                  if (staffList.isEmpty) {
                    return const Center(child: Text('No staff members found. Click "Add Staff Member" to create one.'));
                  }

                  return SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.5),
                        3: FlexColumnWidth(1.5),
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
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CODE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('EMAIL / PHONE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('SHIFT START', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('GRACE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                          ],
                        ),
                        ...staffList.map((s) => TableRow(
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border)),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(s.employeeCode ?? '—', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(s.staffCategory.toUpperCase(), style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(s.email, style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(s.expectedStartTime, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('${s.gracePeriodMinutes} mins', style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: StatusBadge(status: s.status),
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

  void _showAddStaffDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final startTimeCtrl = TextEditingController(text: '08:00');
    final graceCtrl = TextEditingController(text: '15');
    String category = 'teacher';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Staff Member'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *')),
                  const SizedBox(height: 12),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address *')),
                  const SizedBox(height: 12),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Staff Category'),
                    items: const [
                      DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                      DropdownMenuItem(value: 'administrator', child: Text('Administrator')),
                      DropdownMenuItem(value: 'support_staff', child: Text('Support Staff')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startTimeCtrl,
                          decoration: const InputDecoration(labelText: 'Start Time (HH:mm)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: graceCtrl,
                          decoration: const InputDecoration(labelText: 'Grace Period (mins)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty) return;

                final db = ref.read(appDatabaseProvider);
                final userMap = ref.read(k50DeviceUserMapProvider);

                // Allocate next numeric staff ID
                final rangeStart = int.tryParse(await db.settingsDao.getSetting('staff_id_range_start', defaultValue: '8001')) ?? 8001;
                final count = await db.staffDao.countActiveStaff();
                final nextNumeric = rangeStart + count;
                final prefix = category == 'teacher' ? 'TCH' : 'STF';
                final employeeCode = IdGenerator.formatStaffCode(nextNumeric, prefix: prefix);

                final passwordHash = sha256.convert(utf8.encode('Staff123')).toString();

                await db.staffDao.insertStaff(
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  passwordHash: passwordHash,
                  phone: phoneCtrl.text.trim(),
                  staffCategory: category,
                  employeeCode: employeeCode,
                  expectedStartTime: startTimeCtrl.text.trim(),
                  gracePeriodMinutes: int.tryParse(graceCtrl.text.trim()) ?? 15,
                );

                // Map K50 numeric ID to employee code
                await userMap.remember('$nextNumeric', employeeCode);

                ref.invalidate(staffListProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Staff Member'),
            ),
          ],
        ),
      ),
    );
  }
}
