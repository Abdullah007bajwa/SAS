import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/staff_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/hardware/hardware_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/individual_attendance_dialog.dart';
import '../../shared/widgets/k50_enroll_dialog.dart';
import '../../shared/widgets/photo_selector_dialog.dart';
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
                        0: FlexColumnWidth(2.2),
                        1: FlexColumnWidth(1.1),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(1.4),
                        4: FlexColumnWidth(1.1),
                        5: FlexColumnWidth(1.1),
                        6: FlexColumnWidth(0.9),
                        7: FlexColumnWidth(2.0),
                      },
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
                          ),
                          children: [
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STAFF / TEACHER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CODE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('EMAIL / PHONE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('SHIFT START', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('BIOMETRICS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                          ],
                        ),
                        ...staffList.map((s) {
                          final code = s.employeeCode ?? 'EMP-${s.id}';

                          return TableRow(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: AppColors.border)),
                            ),
                            children: [
                              // Avatar & Name
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  children: [
                                    PersonPhotoAvatar(
                                      photoPath: s.photoPath,
                                      name: s.name,
                                      radius: 17,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                          Text(
                                            s.phone.isNotEmpty ? s.phone : 'No phone',
                                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Code
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(code, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                              ),
                              // Category
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(s.staffCategory.toUpperCase(), style: const TextStyle(fontSize: 11)),
                              ),
                              // Email
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(s.email, style: const TextStyle(fontSize: 12)),
                              ),
                              // Shift Start & Grace
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text('${s.expectedStartTime} (${s.gracePeriodMinutes}m)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              ),
                              // Biometrics Status
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: s.fingerprintId != null
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.present.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.fingerprint, size: 14, color: AppColors.present),
                                            SizedBox(width: 4),
                                            Text('Enrolled', style: TextStyle(fontSize: 11, color: AppColors.present, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.fingerprint, size: 14, color: AppColors.textMuted),
                                            SizedBox(width: 4),
                                            Text('Pending', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                          ],
                                        ),
                                      ),
                              ),
                              // Status
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: StatusBadge(status: s.status),
                              ),
                              // Actions Row: History, Edit, Enroll FP
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.history_rounded, size: 18, color: AppColors.primary),
                                      tooltip: 'Attendance History',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        IndividualAttendanceDialog.show(
                                          context,
                                          personType: 'staff',
                                          personId: s.id,
                                          personCode: code,
                                          personName: s.name,
                                          subtitle: '${s.staffCategory.toUpperCase()} • Shift: ${s.expectedStartTime}',
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                                      tooltip: 'Edit Staff Details',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _showEditStaffDialog(context, ref, s),
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: const Icon(Icons.fingerprint, size: 14),
                                      label: Text(
                                        s.fingerprintId != null ? 'Re-enroll' : 'Enroll FP',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      onPressed: () {
                                        K50EnrollDialog.show(
                                          context,
                                          personType: 'staff',
                                          personId: s.id,
                                          personCode: code,
                                          personName: s.name,
                                          existingFingerprintId: s.fingerprintId,
                                          onEnrollmentSuccess: () {
                                            ref.invalidate(staffListProvider);
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
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
    String? selectedPhotoPath;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Staff Member'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Photo Avatar Banner
                  InkWell(
                    onTap: () async {
                      final result = await PhotoSelectorDialog.show(
                        ctx,
                        initialPhotoPath: selectedPhotoPath,
                        personName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'New Staff',
                        personType: 'staff',
                      );
                      if (result != null) {
                        setDialogState(() => selectedPhotoPath = result.isEmpty ? null : result);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          PersonPhotoAvatar(
                            photoPath: selectedPhotoPath,
                            name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'S',
                            radius: 24,
                            backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Staff Profile & Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(
                                  selectedPhotoPath != null ? 'Tap to change photo' : 'Tap to add photo or choose an avatar',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.add_a_photo_outlined, size: 20, color: AppColors.secondary.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *')),
                  const SizedBox(height: 12),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address *')),
                  const SizedBox(height: 12),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Staff Category'),
                    items: const [
                      DropdownMenuItem(value: 'teacher', child: Text('Teacher / Faculty')),
                      DropdownMenuItem(value: 'administrator', child: Text('School Administrator')),
                      DropdownMenuItem(value: 'support_staff', child: Text('Support & Facilities Staff')),
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
                          decoration: const InputDecoration(
                            labelText: 'Expected Shift Start (HH:mm)',
                            hintText: '08:00',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: graceCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Grace Period (Minutes)',
                            hintText: '15',
                          ),
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

                final int rangeStart = int.tryParse(await db.settingsDao.getSetting('staff_id_range_start', defaultValue: '8001')) ?? 8001;
                final allStaff = await db.staffDao.getAllStaff();
                final int nextNumeric = rangeStart + allStaff.length;
                final employeeCode = IdGenerator.formatStaffCode(nextNumeric);

                final bytes = utf8.encode('Staff@1234');
                final passwordHash = sha256.convert(bytes).toString();

                final staffId = await db.staffDao.insertStaff(
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  passwordHash: passwordHash,
                  role: category == 'administrator' ? 'admin' : 'staff',
                  phone: phoneCtrl.text.trim(),
                  staffCategory: category,
                  employeeCode: employeeCode,
                  expectedStartTime: startTimeCtrl.text.trim().isNotEmpty ? startTimeCtrl.text.trim() : '08:00',
                  gracePeriodMinutes: int.tryParse(graceCtrl.text.trim()) ?? 15,
                  photoPath: selectedPhotoPath,
                );

                await userMap.remember('$nextNumeric', employeeCode);

                ref.invalidate(staffListProvider);
                if (ctx.mounted) Navigator.pop(ctx);

                // Immediate Post-Creation Prompt: Enroll Fingerprint Now or Skip For Later
                if (context.mounted) {
                  final enrollNow = await showDialog<bool>(
                    context: context,
                    builder: (pCtx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.check_circle, color: AppColors.present),
                          SizedBox(width: 8),
                          Text('Staff Member Created Successfully'),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$employeeCode — ${nameCtrl.text.trim()} is now registered in the system.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Would you like to register their fingerprint on the K50 biometric terminal now, or skip and do it later?',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(pCtx, false),
                          child: const Text('Skip for Later'),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.fingerprint, size: 16),
                          label: const Text('Enroll Thumb Now on K50'),
                          onPressed: () => Navigator.pop(pCtx, true),
                        ),
                      ],
                    ),
                  );

                  if (enrollNow == true && context.mounted) {
                    K50EnrollDialog.show(
                      context,
                      personType: 'staff',
                      personId: staffId,
                      personCode: employeeCode,
                      personName: nameCtrl.text.trim(),
                      onEnrollmentSuccess: () => ref.invalidate(staffListProvider),
                    );
                  }
                }
              },
              child: const Text('Save Staff Member'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditStaffDialog(BuildContext context, WidgetRef ref, StaffUserData staff) {
    final nameCtrl = TextEditingController(text: staff.name);
    final phoneCtrl = TextEditingController(text: staff.phone);
    final startTimeCtrl = TextEditingController(text: staff.expectedStartTime);
    final graceCtrl = TextEditingController(text: staff.gracePeriodMinutes.toString());
    String category = staff.staffCategory;
    String status = staff.status;
    String? selectedPhotoPath = staff.photoPath;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Edit Staff: ${staff.employeeCode ?? "EMP-${staff.id}"}'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Photo Banner
                  InkWell(
                    onTap: () async {
                      final result = await PhotoSelectorDialog.show(
                        ctx,
                        initialPhotoPath: selectedPhotoPath,
                        personName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : staff.name,
                        personType: 'staff',
                      );
                      if (result != null) {
                        setDialogState(() => selectedPhotoPath = result.isEmpty ? null : result);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          PersonPhotoAvatar(
                            photoPath: selectedPhotoPath,
                            name: staff.name,
                            radius: 24,
                            backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Staff Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(
                                  selectedPhotoPath != null ? 'Tap to change photo' : 'Tap to add photo or choose an avatar',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.add_a_photo_outlined, size: 20, color: AppColors.secondary.withValues(alpha: 0.6)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *')),
                  const SizedBox(height: 12),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Staff Category'),
                    items: const [
                      DropdownMenuItem(value: 'teacher', child: Text('Teacher / Faculty')),
                      DropdownMenuItem(value: 'administrator', child: Text('School Administrator')),
                      DropdownMenuItem(value: 'support_staff', child: Text('Support & Facilities Staff')),
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
                          decoration: const InputDecoration(labelText: 'Expected Shift Start (HH:mm)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: graceCtrl,
                          decoration: const InputDecoration(labelText: 'Grace Period (Minutes)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Employment Status'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => status = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;

                final db = ref.read(appDatabaseProvider);
                await db.staffDao.updateStaff(
                  staff.id,
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  staffCategory: category,
                  expectedStartTime: startTimeCtrl.text.trim().isNotEmpty ? startTimeCtrl.text.trim() : '08:00',
                  gracePeriodMinutes: int.tryParse(graceCtrl.text.trim()) ?? 15,
                  status: status,
                  photoPath: selectedPhotoPath,
                );

                ref.invalidate(staffListProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
