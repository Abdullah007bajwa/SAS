import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/hardware/k50_status_provider.dart';
import '../../core/theme/app_colors.dart';

class K50StatusBadge extends ConsumerWidget {
  const K50StatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(k50StatusProvider);

    Color dotColor;
    Color bgColor;
    Color borderColor;

    switch (status.state) {
      case K50ConnectionState.connected:
        dotColor = AppColors.present;
        bgColor = AppColors.present.withValues(alpha: 0.1);
        borderColor = AppColors.present.withValues(alpha: 0.3);
        break;
      case K50ConnectionState.bridgeOnly:
        dotColor = AppColors.late;
        bgColor = AppColors.late.withValues(alpha: 0.1);
        borderColor = AppColors.late.withValues(alpha: 0.3);
        break;
      case K50ConnectionState.offline:
        dotColor = AppColors.absent;
        bgColor = AppColors.absent.withValues(alpha: 0.1);
        borderColor = AppColors.absent.withValues(alpha: 0.3);
        break;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showDiagnosticDialog(context, ref, status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: dotColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDiagnosticDialog(BuildContext context, WidgetRef ref, K50Status status) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fingerprint, color: AppColors.primary),
            SizedBox(width: 8),
            Text('K50 Biometric Status'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Connection State', status.label),
              const SizedBox(height: 8),
              _buildInfoRow('Reader IP', status.ip ?? '192.168.1.201 (Default)'),
              const SizedBox(height: 8),
              _buildInfoRow('Bridge URL', 'http://127.0.0.1:8787'),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Last Checked',
                DateFormat('HH:mm:ss').format(status.lastChecked),
              ),
              const Divider(height: 24),
              const Text(
                'Diagnostics & State',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                status.details,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Probe Again'),
            onPressed: () {
              ref.read(k50StatusProvider.notifier).checkStatus();
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
