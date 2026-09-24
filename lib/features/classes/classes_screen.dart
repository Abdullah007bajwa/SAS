import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/daos/classes_dao.dart';
import '../../core/database/daos/sections_dao.dart';
import '../../core/database/database_provider.dart';
import '../../core/theme/app_colors.dart';

final classListProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.classesDao.getAllClasses();
});

final sectionListProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.sectionsDao.getAllSections();
});

class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classListProvider);
    final sectionsAsync = ref.watch(sectionListProvider);

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
                  'Academic Classes & Sections',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Configure grades, sections, and room capacity for student rosters',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Section'),
                  onPressed: () => _showAddSectionDialog(context, ref),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Class / Grade'),
                  onPressed: () => _showAddClassDialog(context, ref),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Classes & Sections Grid
        Expanded(
          child: classesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading classes: $e')),
            data: (classes) {
              if (classes.isEmpty) {
                return const Center(child: Text('No classes found. Click "Add Class" to create one.'));
              }

              return sectionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading sections: $e')),
                data: (sections) {
                  return ListView.separated(
                    itemCount: classes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final c = classes[index];
                      final classSections = sections.where((s) => s.classId == c.id).toList();

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.class_, color: AppColors.primary, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.name,
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                          if (c.description != null && c.description!.isNotEmpty)
                                            Text(
                                              c.description!,
                                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${c.studentCount} Students Enrolled',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              const Text('SECTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                              const SizedBox(height: 8),
                              if (classSections.isEmpty)
                                const Text('No sections configured yet for this grade.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
                              else
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: classSections.map((s) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.meeting_room, size: 16, color: AppColors.textSecondary),
                                          const SizedBox(width: 8),
                                          Text(
                                            s.name,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          if (s.roomNumber != null) ...[
                                            const SizedBox(width: 6),
                                            Text('(${s.roomNumber})', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                          ],
                                          const SizedBox(width: 10),
                                          Text(
                                            '${s.studentCount}/${s.capacity}',
                                            style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddClassDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Class / Grade'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Class Name (e.g. Grade 2)')),
            const SizedBox(height: 12),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Numeric Grade Level (e.g. 2)'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final db = ref.read(appDatabaseProvider);
              await db.classesDao.insertClass(
                name: nameCtrl.text.trim(),
                numericGrade: int.tryParse(gradeCtrl.text.trim()),
                description: descCtrl.text.trim(),
              );
              ref.invalidate(classListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Class'),
          ),
        ],
      ),
    );
  }

  void _showAddSectionDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final classes = await db.classesDao.getAllClasses();
    if (!context.mounted || classes.isEmpty) return;

    final nameCtrl = TextEditingController();
    final roomCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '40');
    int selectedClassId = classes.first.id;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Section'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: selectedClassId,
                decoration: const InputDecoration(labelText: 'Class / Grade'),
                items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedClassId = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Section Name (e.g. Section B)')),
              const SizedBox(height: 12),
              TextField(controller: roomCtrl, decoration: const InputDecoration(labelText: 'Room Number (e.g. 102)')),
              const SizedBox(height: 12),
              TextField(controller: capacityCtrl, decoration: const InputDecoration(labelText: 'Student Capacity'), keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await db.sectionsDao.insertSection(
                  classId: selectedClassId,
                  name: nameCtrl.text.trim(),
                  roomNumber: roomCtrl.text.trim(),
                  capacity: int.tryParse(capacityCtrl.text.trim()) ?? 40,
                );
                ref.invalidate(sectionListProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Section'),
            ),
          ],
        ),
      ),
    );
  }
}
