import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/students_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/hardware/hardware_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/individual_attendance_dialog.dart';
import '../../shared/widgets/k50_enroll_dialog.dart';
import '../../shared/widgets/photo_selector_dialog.dart';
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
                  'Manage student enrollment, class assignments, parent contacts, and K50 biometric profiles',
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
                        0: FlexColumnWidth(2.2),
                        1: FlexColumnWidth(1.1),
                        2: FlexColumnWidth(1.4),
                        3: FlexColumnWidth(1.3),
                        4: FlexColumnWidth(1.2),
                        5: FlexColumnWidth(0.9),
                        6: FlexColumnWidth(2.0),
                      },
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
                          ),
                          children: [
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STUDENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CODE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('CLASS & SECTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('PARENT PHONE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('BIOMETRICS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary))),
                          ],
                        ),
                        ...students.map((s) {
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
                                            s.parentName.isNotEmpty ? 'Parent: ${s.parentName}' : 'No parent recorded',
                                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Student Code
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(s.studentCode, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                              ),
                              // Class & Section
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  s.className != null ? '${s.className} (${s.sectionName ?? "A"})' : 'Unassigned',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              // Parent Phone
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(s.parentPhone.isEmpty ? '—' : s.parentPhone, style: const TextStyle(fontSize: 12)),
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
                                child: StatusBadge(status: s.enrollmentStatus),
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
                                          personType: 'student',
                                          personId: s.id,
                                          personCode: s.studentCode,
                                          personName: s.name,
                                          subtitle: s.className != null ? '${s.className} (${s.sectionName ?? "A"})' : null,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                                      tooltip: 'Edit Student Details',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _showEditStudentDialog(context, ref, s),
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
                                          personType: 'student',
                                          personId: s.id,
                                          personCode: s.studentCode,
                                          personName: s.name,
                                          existingFingerprintId: s.fingerprintId,
                                          onEnrollmentSuccess: () {
                                            ref.invalidate(studentListProvider);
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
    String? selectedPhotoPath;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredSections = sections.where((s) => s.classId == selectedClassId).toList();

          return AlertDialog(
            title: const Text('Enroll New Student'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Profile Photo / Avatar Banner
                    InkWell(
                      onTap: () async {
                        final result = await PhotoSelectorDialog.show(
                          ctx,
                          initialPhotoPath: selectedPhotoPath,
                          personName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'New Student',
                          personType: 'student',
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
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Student Profile Picture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(
                                    selectedPhotoPath != null ? 'Tap to change photo' : 'Tap to add photo or choose an avatar',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.add_a_photo_outlined, size: 20, color: AppColors.primary.withValues(alpha: 0.6)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Student Full Name *'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedClassId,
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
                            initialValue: selectedSectionId,
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
                  final int rangeStart = int.tryParse(await db.settingsDao.getSetting('student_id_range_start', defaultValue: '1001')) ?? 1001;
                  final int count = await db.studentsDao.countActiveStudents();
                  final int nextNumeric = rangeStart + count;
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
                    photoPath: selectedPhotoPath,
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

                  // Immediate Post-Enrollment Prompt: Enroll Fingerprint Now or Skip For Later
                  if (context.mounted) {
                    final enrollNow = await showDialog<bool>(
                      context: context,
                      builder: (pCtx) => AlertDialog(
                        title: const Row(
                          children: [
                            Icon(Icons.check_circle, color: AppColors.present),
                            SizedBox(width: 8),
                            Text('Student Enrolled Successfully'),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$studentCode — ${nameCtrl.text.trim()} has been registered in the database.',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Would you like to enroll their fingerprint on the K50 terminal now, or skip and do it later?',
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
                        personType: 'student',
                        personId: studentId,
                        personCode: studentCode,
                        personName: nameCtrl.text.trim(),
                        onEnrollmentSuccess: () => ref.invalidate(studentListProvider),
                      );
                    }
                  }
                },
                child: const Text('Save Student'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditStudentDialog(BuildContext context, WidgetRef ref, StudentWithEnrollment student) async {
    final db = ref.read(appDatabaseProvider);
    final classes = await db.classesDao.getAllClasses();
    final sections = await db.sectionsDao.getAllSections();

    if (!context.mounted) return;

    final nameCtrl = TextEditingController(text: student.name);
    final parentNameCtrl = TextEditingController(text: student.parentName);
    final parentPhoneCtrl = TextEditingController(text: student.parentPhone);
    final whatsappPhoneCtrl = TextEditingController(text: student.whatsappPhone);

    int? selectedClassId = student.classId ?? (classes.isNotEmpty ? classes.first.id : null);
    int? selectedSectionId = student.sectionId ?? (sections.isNotEmpty ? sections.first.id : null);
    bool notificationOptIn = student.notificationOptIn == 1;
    String enrollmentStatus = student.enrollmentStatus;
    String? selectedPhotoPath = student.photoPath;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredSections = sections.where((s) => s.classId == selectedClassId).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Edit Student: ${student.studentCode}'),
              ],
            ),
            content: SizedBox(
              width: 500,
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
                          personName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : student.name,
                          personType: 'student',
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
                              name: student.name,
                              radius: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Student Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(
                                    selectedPhotoPath != null ? 'Tap to change photo' : 'Tap to add photo or choose an avatar',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.add_a_photo_outlined, size: 20, color: AppColors.primary.withValues(alpha: 0.6)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Student Full Name *'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedClassId,
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
                            initialValue: selectedSectionId,
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
                    DropdownButtonFormField<String>(
                      initialValue: enrollmentStatus,
                      decoration: const InputDecoration(labelText: 'Enrollment Status'),
                      items: const [
                        DropdownMenuItem(value: 'enrolled', child: Text('Enrolled (Active)')),
                        DropdownMenuItem(value: 'withdrawn', child: Text('Withdrawn')),
                        DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                        DropdownMenuItem(value: 'graduated', child: Text('Graduated')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => enrollmentStatus = val);
                      },
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

                  // Update student row
                  await db.studentsDao.updateStudent(
                    student.id,
                    name: nameCtrl.text.trim(),
                    parentName: parentNameCtrl.text.trim(),
                    parentPhone: parentPhoneCtrl.text.trim(),
                    whatsappPhone: whatsappPhoneCtrl.text.trim(),
                    notificationOptIn: notificationOptIn ? 1 : 0,
                    enrollmentStatus: enrollmentStatus,
                    photoPath: selectedPhotoPath,
                  );

                  // If class or section changed, update enrollment
                  if (selectedClassId != null && selectedSectionId != null &&
                      (selectedClassId != student.classId || selectedSectionId != student.sectionId)) {
                    await db.enrollmentsDao.enrollStudent(
                      studentId: student.id,
                      classId: selectedClassId!,
                      sectionId: selectedSectionId!,
                      academicYear: '2026-2027',
                    );
                  }

                  ref.invalidate(studentListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }
}
