import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/classes_dao.dart';
import '../../core/database/daos/sections_dao.dart';
import '../../core/database/daos/students_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/hardware/hardware_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/status_badge.dart';
import '../../utils/id_generator.dart';

final studentSearchQueryProvider = StateProvider<String>((ref) => '');

final studentListProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final query = ref.watch(studentSearchQueryProvider);
  return db.studentsDao.getAllStudents(query: query);
});

class StudentsScreen extends ConsumerWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(studentListProvider);

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
                  'Students & Rosters',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage student enrollment, class assignments, and parent contact details',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Enroll New Student'),
              onPressed: () => _showEnrollStudentDialog(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Search Bar
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by student name, code (e.g. STU-1001), or parent phone...',
                prefixIcon: Icon(Icons.search, size: 20),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (val) {
                ref.read(studentSearchQueryProvider.notifier).state = val;
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Students Table
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: studentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading students: $e')),
                data: (students) {
                  if (students.isEmpty) {
                    return const Center(
                      child: Text(
                        'No students found. Click "Enroll New Student" to add one.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.5),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(1.5),
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
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STUDENT CODE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CLASS & SECTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('PARENT NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('PARENT PHONE (SMS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('ALERTS OPT-IN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                          ],
                        ),
                        ...students.map((s) => TableRow(
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
                              child: Text(s.studentCode, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                s.className != null ? '${s.className} (${s.sectionName ?? "A"})' : 'Unassigned',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(s.parentName.isEmpty ? '—' : s.parentName),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(s.parentPhone.isEmpty ? '—' : s.parentPhone, style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Icon(
                                s.notificationOptIn == 1 ? Icons.notifications_active : Icons.notifications_off,
                                size: 18,
                                color: s.notificationOptIn == 1 ? AppColors.present : AppColors.textMuted,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: StatusBadge(status: s.enrollmentStatus),
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

  void _showEnrollStudentDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final userMap = ref.read(k50DeviceUserMapProvider);
    final classes = await db.classesDao.getAllClasses();
    final sections = await db.sectionsDao.getAllSections();

    if (!context.mounted) return;

    final nameCtrl = TextEditingController();
    final parentNameCtrl = TextEditingController();
    final parentPhoneCtrl = TextEditingController();
    final whatsappPhoneCtrl = TextEditingController();

    int? selectedClassId = classes.isNotEmpty ? classes.first.id : null;
    int? selectedSectionId = sections.isNotEmpty ? sections.first.id : null;
    bool notificationOptIn = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredSections = sections.where((s) => s.classId == selectedClassId).toList();

          return AlertDialog(
            title: const Text('Enroll New Student'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Student Full Name *'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selectedClassId,
                            decoration: const InputDecoration(labelText: 'Class / Grade'),
                            items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                selectedClassId = val;
                                final sub = sections.where((s) => s.classId == val).toList();
                                selectedSectionId = sub.isNotEmpty ? sub.first.id : null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: selectedSectionId,
                            decoration: const InputDecoration(labelText: 'Section'),
                            items: filteredSections.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                            onChanged: (val) => setDialogState(() => selectedSectionId = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: parentNameCtrl,
                      decoration: const InputDecoration(labelText: 'Parent / Guardian Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: parentPhoneCtrl,
                      decoration: const InputDecoration(labelText: 'Parent Phone (for SMS Alerts)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: whatsappPhoneCtrl,
                      decoration: const InputDecoration(labelText: 'Parent WhatsApp Number'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Enable Parent Absence Notifications'),
                      subtitle: const Text('Send SMS and WhatsApp if student is absent past cutoff'),
                      value: notificationOptIn,
                      onChanged: (val) => setDialogState(() => notificationOptIn = val),
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

                  // Allocate next numeric student code
                  final rangeStart = int.tryParse(await db.settingsDao.getSetting('student_id_range_start', defaultValue: '1001')) ?? 1001;
                  final count = await db.studentsDao.countActiveStudents();
                  final nextNumeric = rangeStart + count;
                  final studentCode = IdGenerator.formatStudentCode(nextNumeric);

                  final studentId = await db.studentsDao.insertStudent(
                    studentCode: studentCode,
                    name: nameCtrl.text.trim(),
                    parentName: parentNameCtrl.text.trim(),
                    parentPhone: parentPhoneCtrl.text.trim(),
                    whatsappPhone: whatsappPhoneCtrl.text.trim().isNotEmpty
                        ? whatsappPhoneCtrl.text.trim()
                        : parentPhoneCtrl.text.trim(),
                    notificationOptIn: notificationOptIn ? 1 : 0,
                  );

                  // Map K50 numeric ID to student code
                  await userMap.remember('$nextNumeric', studentCode);

                  // Enroll in class/section
                  if (selectedClassId != null && selectedSectionId != null) {
                    await db.enrollmentsDao.enrollStudent(
                      studentId: studentId,
                      classId: selectedClassId!,
                      sectionId: selectedSectionId!,
                      academicYear: '2026-2027',
                    );
                  }

                  ref.invalidate(studentListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save & Enroll'),
              ),
            ],
          );
        },
      ),
    );
  }
}
