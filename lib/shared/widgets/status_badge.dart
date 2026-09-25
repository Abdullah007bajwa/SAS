import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'present':
        bg = AppColors.present.withValues(alpha: 0.12);
        fg = AppColors.present;
        break;
      case 'late':
        bg = AppColors.late.withValues(alpha: 0.12);
        fg = AppColors.late;
        break;
      case 'absent':
        bg = AppColors.absent.withValues(alpha: 0.12);
        fg = AppColors.absent;
        break;
      case 'enrolled':
      case 'active':
        bg = AppColors.secondary.withValues(alpha: 0.12);
        fg = AppColors.secondary;
        break;
      case 'sent':
      case 'success':
        bg = AppColors.present.withValues(alpha: 0.12);
        fg = AppColors.present;
        break;
      case 'failed':
        bg = AppColors.absent.withValues(alpha: 0.12);
        fg = AppColors.absent;
        break;
      default:
        bg = AppColors.textMuted.withValues(alpha: 0.12);
        fg = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
