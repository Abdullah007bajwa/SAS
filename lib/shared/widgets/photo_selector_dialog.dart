import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/desktop_file_picker.dart';

/// Preset avatar metadata for schools.
class AvatarPreset {
  final String key;
  final String label;
  final IconData icon;
  final Color bgColor;
  final Color iconColor;

  const AvatarPreset({
    required this.key,
    required this.label,
    required this.icon,
    required this.bgColor,
    required this.iconColor,
  });
}

const List<AvatarPreset> kSchoolAvatarPresets = [
  AvatarPreset(
    key: 'avatar:boy_1',
    label: 'Junior Boy',
    icon: Icons.face,
    bgColor: Color(0xFFE0F2FE),
    iconColor: Color(0xFF0284C7),
  ),
  AvatarPreset(
    key: 'avatar:boy_2',
    label: 'Senior Boy',
    icon: Icons.person,
    bgColor: Color(0xFFE0E7FF),
    iconColor: Color(0xFF4F46E5),
  ),
  AvatarPreset(
    key: 'avatar:girl_1',
    label: 'Junior Girl',
    icon: Icons.face_3,
    bgColor: Color(0xFFFCE7F3),
    iconColor: Color(0xFFDB2777),
  ),
  AvatarPreset(
    key: 'avatar:girl_2',
    label: 'Senior Girl',
    icon: Icons.person_3,
    bgColor: Color(0xFFF3E8FF),
    iconColor: Color(0xFF9333EA),
  ),
  AvatarPreset(
    key: 'avatar:scholar',
    label: 'Honor Scholar',
    icon: Icons.school,
    bgColor: Color(0xFFFEF3C7),
    iconColor: Color(0xFFD97706),
  ),
  AvatarPreset(
    key: 'avatar:teacher_m',
    label: 'Male Faculty',
    icon: Icons.co_present,
    bgColor: Color(0xFFDCFCE7),
    iconColor: Color(0xFF16A34A),
  ),
  AvatarPreset(
    key: 'avatar:teacher_f',
    label: 'Female Faculty',
    icon: Icons.co_present_outlined,
    bgColor: Color(0xFFFFEDD5),
    iconColor: Color(0xFFEA580C),
  ),
  AvatarPreset(
    key: 'avatar:staff_admin',
    label: 'Admin Staff',
    icon: Icons.badge,
    bgColor: Color(0xFFF1F5F9),
    iconColor: Color(0xFF475569),
  ),
];

/// Reusable avatar widget that handles file images, preset avatars, and name initials.
class PersonPhotoAvatar extends StatelessWidget {
  const PersonPhotoAvatar({
    super.key,
    required this.photoPath,
    required this.name,
    this.radius = 20,
    this.backgroundColor,
  });

  final String? photoPath;
  final String name;
  final double radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final path = photoPath?.trim();

    // 1. Check if it's an avatar preset
    if (path != null && path.startsWith('avatar:')) {
      final preset = kSchoolAvatarPresets.firstWhere(
        (p) => p.key == path,
        orElse: () => kSchoolAvatarPresets.first,
      );
      return CircleAvatar(
        radius: radius,
        backgroundColor: preset.bgColor,
        child: Icon(preset.icon, color: preset.iconColor, size: radius * 1.1),
      );
    }

    // 2. Check if it's a valid local file image
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor ?? AppColors.primary.withValues(alpha: 0.1),
          backgroundImage: FileImage(file),
        );
      }
    }

    // 3. Fallback to initials
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}

/// Interactive dialog for choosing or changing student/staff photo.
class PhotoSelectorDialog extends StatefulWidget {
  const PhotoSelectorDialog({
    super.key,
    this.initialPhotoPath,
    required this.personName,
    required this.personType,
  });

  final String? initialPhotoPath;
  final String personName;
  final String personType;

  static Future<String?> show(
    BuildContext context, {
    String? initialPhotoPath,
    required String personName,
    required String personType,
  }) {
    return showDialog<String?>(
      context: context,
      builder: (ctx) => PhotoSelectorDialog(
        initialPhotoPath: initialPhotoPath,
        personName: personName,
        personType: personType,
      ),
    );
  }

  @override
  State<PhotoSelectorDialog> createState() => _PhotoSelectorDialogState();
}

class _PhotoSelectorDialogState extends State<PhotoSelectorDialog> {
  late TextEditingController _pathController;
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.initialPhotoPath;
    _pathController = TextEditingController(
      text: widget.initialPhotoPath != null && !widget.initialPhotoPath!.startsWith('avatar:')
          ? widget.initialPhotoPath
          : '',
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _browseFiles() async {
    final picked = await DesktopFilePicker.pickImageFile();
    if (picked != null) {
      setState(() {
        _selectedPath = picked;
        _pathController.text = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select ${widget.personType.toUpperCase()} Photo',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                widget.personName,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Preview Box
              Center(
                child: Column(
                  children: [
                    PersonPhotoAvatar(
                      photoPath: _selectedPath,
                      name: widget.personName,
                      radius: 44,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedPath == null
                          ? 'No photo set (using default initials)'
                          : _selectedPath!.startsWith('avatar:')
                              ? 'Selected: Preset Avatar'
                              : 'Selected: File on disk',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Action button to browse computer
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _browseFiles,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Browse Photo from Computer...'),
                ),
              ),
              const SizedBox(height: 20),

              const Divider(),
              const SizedBox(height: 10),

              // Presets Section
              const Text(
                'Or Choose a School Avatar Preset:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: kSchoolAvatarPresets.map((preset) {
                  final isSelected = _selectedPath == preset.key;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPath = preset.key;
                        _pathController.clear();
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: preset.bgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(preset.icon, color: preset.iconColor, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            preset.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),

              // Manual File Path
              const Text(
                'Or specify image path manually:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _pathController,
                decoration: InputDecoration(
                  hintText: Platform.isWindows ? r'C:\Photos\student.jpg' : '/home/user/photos/student.jpg',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check, size: 18),
                    onPressed: () {
                      final text = _pathController.text.trim();
                      if (text.isNotEmpty) {
                        setState(() => _selectedPath = text);
                      }
                    },
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    setState(() => _selectedPath = val.trim());
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_selectedPath != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''), // empty string represents remove
            child: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selectedPath ?? ''),
          child: const Text('Save Photo'),
        ),
      ],
    );
  }
}

