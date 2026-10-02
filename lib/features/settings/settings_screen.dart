import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_backup_service.dart';
import '../../core/database/database_provider.dart';
import '../../core/database/demo_seeder.dart';
import '../../core/hardware/hardware_providers.dart';
import '../../core/notifications/notification_providers.dart';
import '../../core/theme/app_colors.dart';

final settingsMapProvider = FutureProvider.autoDispose((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.settingsDao.getAllSettings();
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _schoolNameCtrl = TextEditingController();
  final _cutoffTimeCtrl = TextEditingController();
  final _closingTimeCtrl = TextEditingController();
  final _gracePeriodCtrl = TextEditingController();
  final _studentStartCtrl = TextEditingController();
  final _studentEndCtrl = TextEditingController();
  final _staffStartCtrl = TextEditingController();
  final _staffEndCtrl = TextEditingController();
  final _k50IpCtrl = TextEditingController();
  final _k50PortCtrl = TextEditingController();
  final _bridgePortCtrl = TextEditingController();

  final _twilioSidCtrl = TextEditingController();
  final _twilioTokenCtrl = TextEditingController();
  final _twilioPhoneCtrl = TextEditingController();
  final _twilioWaFromCtrl = TextEditingController();
  final _smsTemplateCtrl = TextEditingController();
  final _waTemplateCtrl = TextEditingController();

  final _androidGatewayUrlCtrl = TextEditingController();
  final _androidGatewayUserCtrl = TextEditingController();
  final _androidGatewayPassCtrl = TextEditingController();
  final _smsThrottleSecCtrl = TextEditingController();
  final _checkinSmsTemplateCtrl = TextEditingController();

  String _smsProvider = 'android_gateway';
  bool _smsEnabled = false;
  bool _checkinSmsEnabled = true;
  bool _waEnabled = false;
  bool _initialized = false;

  List<BackupItem> _backups = [];
  bool _loadingBackups = false;
  String? _integrityStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBackups();
    });
  }

  @override
  void dispose() {
    _schoolNameCtrl.dispose();
    _cutoffTimeCtrl.dispose();
    _closingTimeCtrl.dispose();
    _gracePeriodCtrl.dispose();
    _studentStartCtrl.dispose();
    _studentEndCtrl.dispose();
    _staffStartCtrl.dispose();
    _staffEndCtrl.dispose();
    _k50IpCtrl.dispose();
    _k50PortCtrl.dispose();
    _bridgePortCtrl.dispose();
    _twilioSidCtrl.dispose();
    _twilioTokenCtrl.dispose();
    _twilioPhoneCtrl.dispose();
    _twilioWaFromCtrl.dispose();
    _smsTemplateCtrl.dispose();
    _waTemplateCtrl.dispose();
    _androidGatewayUrlCtrl.dispose();
    _androidGatewayUserCtrl.dispose();
    _androidGatewayPassCtrl.dispose();
    _smsThrottleSecCtrl.dispose();
    _checkinSmsTemplateCtrl.dispose();
    super.dispose();
  }

  void _populate(Map<String, String> s) {
    if (_initialized) return;
    _initialized = true;

    _schoolNameCtrl.text = s['school_name'] ?? 'School Attendance Portal';
    _cutoffTimeCtrl.text = s['student_cutoff_time'] ?? '08:30';
    _closingTimeCtrl.text = s['student_closing_time'] ?? '14:00';
    _gracePeriodCtrl.text = s['attendance_grace_period'] ?? '15';
    _studentStartCtrl.text = s['student_id_range_start'] ?? '1001';
    _studentEndCtrl.text = s['student_id_range_end'] ?? '7999';
    _staffStartCtrl.text = s['staff_id_range_start'] ?? '8001';
    _staffEndCtrl.text = s['staff_id_range_end'] ?? '8999';
    _k50IpCtrl.text = s['k50_ip'] ?? '192.168.18.78';
    _k50PortCtrl.text = s['k50_port'] ?? '4370';
    _bridgePortCtrl.text = s['k50_bridge_port'] ?? '8787';

    _smsProvider = s['sms_provider'] ?? 'android_gateway';
    _smsEnabled = s['sms_enabled'] == 'true';
    _checkinSmsEnabled = s['sms_checkin_enabled'] != 'false';
    _waEnabled = s['whatsapp_enabled'] == 'true';

    _androidGatewayUrlCtrl.text = s['sms_gateway_url'] ?? 'http://192.168.18.132:8080';
    _androidGatewayUserCtrl.text = s['sms_gateway_username'] ?? 'sms';
    _androidGatewayPassCtrl.text = s['sms_gateway_password'] ?? 'cWPHrhs5';
    _smsThrottleSecCtrl.text = s['sms_throttle_delay_sec'] ?? '2.5';
    _checkinSmsTemplateCtrl.text = s['checkin_sms_template'] ??
        'Dear Parent, your child {student_name} arrived at school at {time} on {date}. Status: {status}. - {school_name}';

    _twilioSidCtrl.text = s['twilio_account_sid'] ?? '';
    _twilioTokenCtrl.text = s['twilio_auth_token'] ?? '';
    _twilioPhoneCtrl.text = s['twilio_from_phone'] ?? '';
    _twilioWaFromCtrl.text = s['twilio_whatsapp_from'] ?? '';
    _smsTemplateCtrl.text = s['absence_sms_template'] ??
        'Dear Parent, your child {student_name} is marked ABSENT today ({date}).';
    _waTemplateCtrl.text = s['absence_whatsapp_template'] ??
        'Dear Parent, your child {student_name} is marked ABSENT today ({date}).';
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsMapProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading settings: $e')),
      data: (settings) {
        _populate(settings);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'School & Biometric Configuration',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Configure K50 hardware integration, ID allocation, cutoff rules, and parent alerts',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.absent,
                          side: const BorderSide(color: AppColors.absent),
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: const Text('Clear All Dummy Data'),
                        onPressed: _clearDummyData,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.dataset_outlined, size: 16),
                        label: const Text('Seed Demo Data'),
                        onPressed: _seedDemoData,
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Save Configuration'),
                        onPressed: _saveSettings,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Section 1: School & Cutoff Rules
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.schedule, color: AppColors.primary, size: 20),
                          SizedBox(width: 8),
                          Text('Attendance & Arrival Rules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _schoolNameCtrl,
                              decoration: const InputDecoration(labelText: 'School Name'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _cutoffTimeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Arrival Cutoff (HH:mm)',
                                hintText: '08:30',
                                helperText: 'After this is Late',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _closingTimeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'School Closing (HH:mm)',
                                hintText: '14:00',
                                helperText: 'After this stays Absent',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _gracePeriodCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Teacher Grace (min)',
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
              const SizedBox(height: 16),

              // Section 2: Non-Overlapping ID Range Allocation (K50 3,000 Capacity)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.pin, color: AppColors.primary, size: 20),
                          SizedBox(width: 8),
                          Text('Biometric Device ID Range Allocation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ZKTeco K50 supports 3,000 users. Separate numeric ranges ensure students and staff never collide on-device.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _studentStartCtrl,
                              decoration: const InputDecoration(labelText: 'Student ID Range Start'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _studentEndCtrl,
                              decoration: const InputDecoration(labelText: 'Student ID Range End'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: TextField(
                              controller: _staffStartCtrl,
                              decoration: const InputDecoration(labelText: 'Staff ID Range Start'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _staffEndCtrl,
                              decoration: const InputDecoration(labelText: 'Staff ID Range End'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Section 3: Hardware Connection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.router, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text('ZKTeco K50 Hardware Connection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.network_check, size: 16),
                            label: const Text('Test Bridge Health'),
                            onPressed: _testBridge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _k50IpCtrl,
                              decoration: const InputDecoration(labelText: 'Device IP Address', hintText: '192.168.1.201'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _k50PortCtrl,
                              decoration: const InputDecoration(labelText: 'Device TCP Port', hintText: '4370'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _bridgePortCtrl,
                              decoration: const InputDecoration(labelText: 'C# Bridge Local Port', hintText: '8787'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Section 4: Parent Alerts & SMS Gateway
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sms_outlined, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Parent Alerts & SMS Notification System',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.send_to_mobile, size: 16),
                            label: const Text('Send Test SMS'),
                            onPressed: _openTestSmsDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Automate instant SMS check-in notifications when students punch at K50, plus absence alerts at cutoff time.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),

                      // Notification Toggles
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 280,
                            child: SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Master SMS Switch', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Enable or disable all outgoing SMS'),
                              value: _smsEnabled,
                              onChanged: (val) => setState(() => _smsEnabled = val),
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Real-Time Check-In Alerts', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Send instant SMS when student punches at K50'),
                              value: _checkinSmsEnabled,
                              onChanged: (val) => setState(() => _checkinSmsEnabled = val),
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('WhatsApp Alerts (Twilio)', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Send WhatsApp message on cutoff absence'),
                              value: _waEnabled,
                              onChanged: (val) => setState(() => _waEnabled = val),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),

                      // Provider Selection
                      const Text(
                        'SMS Provider Architecture',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'android_gateway',
                            icon: Icon(Icons.phone_android),
                            label: Text('Local Android Gateway (Zero Fee - Mobile SIM)'),
                          ),
                          ButtonSegment<String>(
                            value: 'twilio',
                            icon: Icon(Icons.cloud_outlined),
                            label: Text('Twilio Cloud SMS (Paid API)'),
                          ),
                        ],
                        selected: {_smsProvider},
                        onSelectionChanged: (newSelection) {
                          setState(() => _smsProvider = newSelection.first);
                        },
                      ),
                      const SizedBox(height: 16),

                      if (_smsProvider == 'android_gateway') ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.cell_tower, color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '• How it works: Run an open-source SMS Gateway app on an Android phone connected to the school Wi-Fi (e.g., "SMS Gateway for Android" by capcom6 or "Textbee"). The desktop app posts messages over HTTP directly to the phone.\n'
                                  '• Anti-Spam Carrier Pacing: 2.5s sequential delay between SMS protects your SIM from mobile operator anti-spam blocks during arrival rush.',
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey[800], height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _androidGatewayUrlCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Android Gateway IP & Port',
                                  hintText: 'http://192.168.18.50:8080',
                                  prefixIcon: Icon(Icons.wifi),
                                  helperText: 'Enter phone local IP and port displayed on gateway app',
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _smsThrottleSecCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Carrier Throttle Delay (sec)',
                                  hintText: '2.5',
                                  helperText: 'Delay between consecutive SMS',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _androidGatewayUserCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Gateway Login / API Key (Optional)',
                                  hintText: 'admin or leave empty',
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _androidGatewayPassCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Gateway Password / Secret Token (Optional)',
                                  hintText: 'Leave empty if unauthenticated',
                                ),
                                obscureText: true,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _twilioSidCtrl,
                                decoration: const InputDecoration(labelText: 'Twilio Account SID'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _twilioTokenCtrl,
                                decoration: const InputDecoration(labelText: 'Twilio Auth Token'),
                                obscureText: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _twilioPhoneCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Twilio Sender Phone (SMS)',
                                  hintText: '+1234567890',
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _twilioWaFromCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Twilio WhatsApp Sender',
                                  hintText: '+14155238886',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const Divider(height: 28),
                      const Text(
                        'Notification Templates',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _checkinSmsTemplateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Real-Time Check-In SMS Template',
                          helperText: 'Placeholders: {student_name}, {time}, {date}, {status}, {school_name}',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _smsTemplateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Absence Cutoff SMS Template',
                          helperText: 'Placeholders: {student_name}, {date}',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _waTemplateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Absence Cutoff WhatsApp Template',
                          helperText: 'Placeholders: {student_name}, {date}',
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Section 4: Local Database Crash Protection & Backups
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Local Database Backup & Crash Protection',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.health_and_safety_outlined, size: 16),
                                label: const Text('Verify Integrity'),
                                onPressed: _checkIntegrity,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.folder_open_outlined, size: 16),
                                label: const Text('Open Backups Folder'),
                                onPressed: _openBackupFolder,
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.backup_outlined, size: 16),
                                label: const Text('Backup System Now (DB + Photos)'),
                                onPressed: _createBackupNow,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'SQLite WAL (Write-Ahead Logging) is enabled for maximum crash resilience against power cuts and system freezes. '
                                'Complete backups (.zip bundling SQLite database + student/staff profile pictures) are saved locally to your Documents directory, with the last 14 snapshots kept.',
                                style: TextStyle(fontSize: 12, color: Colors.blueGrey[800], height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_integrityStatus != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Last Integrity Check: $_integrityStatus',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _integrityStatus == 'ok' ? AppColors.present : AppColors.absent,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text('Recent Backups', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (_loadingBackups)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_backups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No backup snapshots created yet. Click "Backup System Now" to create your first snapshot.',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _backups.length > 5 ? 5 : _backups.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final b = _backups[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                b.isAutomatic ? Icons.schedule : Icons.save_alt,
                                color: b.isAutomatic ? AppColors.primary : AppColors.present,
                                size: 20,
                              ),
                              title: Text(b.fileName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                              subtitle: Text(
                                '${b.formattedDate} • ${b.formattedSize}${b.isZip ? " • Full (DB + Photos)" : " • DB"}${b.isAutomatic ? " (Daily Auto)" : " (Manual)"}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                              trailing: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.restore_page_outlined, size: 14),
                                label: const Text('Restore', style: TextStyle(fontSize: 12)),
                                onPressed: () => _restoreBackup(b),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Section 5: Data Management & Clean School Reset
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.cleaning_services_outlined, color: AppColors.absent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Data Management & Reset to Clean School',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Purge all demo and test data (fake students, sample staff, dummy attendance records, logs). '
                        'Your System Administrator credentials and School Configuration will be preserved so the school can start with clean rosters.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.absent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.delete_forever, size: 16),
                            label: const Text('Wipe All Dummy / Test Data'),
                            onPressed: _clearDummyData,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.dataset_outlined, size: 16),
                            label: const Text('Load Demo School Data'),
                            onPressed: _seedDemoData,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  void _saveSettings() async {
    final db = ref.read(appDatabaseProvider);

    await db.settingsDao.setSetting('school_name', _schoolNameCtrl.text.trim());
    await db.settingsDao.setSetting('student_cutoff_time', _cutoffTimeCtrl.text.trim());
    await db.settingsDao.setSetting('student_closing_time', _closingTimeCtrl.text.trim());
    await db.settingsDao.setSetting('attendance_grace_period', _gracePeriodCtrl.text.trim());
    await db.settingsDao.setSetting('student_id_range_start', _studentStartCtrl.text.trim());
    await db.settingsDao.setSetting('student_id_range_end', _studentEndCtrl.text.trim());
    await db.settingsDao.setSetting('staff_id_range_start', _staffStartCtrl.text.trim());
    await db.settingsDao.setSetting('staff_id_range_end', _staffEndCtrl.text.trim());
    
    final targetIp = _k50IpCtrl.text.trim();
    final targetPort = int.tryParse(_k50PortCtrl.text.trim()) ?? 4370;
    await db.settingsDao.setSetting('k50_ip', targetIp);
    await db.settingsDao.setSetting('k50_port', targetPort.toString());
    await db.settingsDao.setSetting('k50_bridge_port', _bridgePortCtrl.text.trim());

    await db.settingsDao.setSetting('sms_provider', _smsProvider);
    await db.settingsDao.setSetting('sms_enabled', _smsEnabled ? 'true' : 'false');
    await db.settingsDao.setSetting('sms_checkin_enabled', _checkinSmsEnabled ? 'true' : 'false');
    await db.settingsDao.setSetting('sms_gateway_url', _androidGatewayUrlCtrl.text.trim());
    await db.settingsDao.setSetting('sms_gateway_username', _androidGatewayUserCtrl.text.trim());
    if (_androidGatewayPassCtrl.text.trim().isNotEmpty) {
      await db.settingsDao.setSetting('sms_gateway_password', _androidGatewayPassCtrl.text.trim());
    }
    await db.settingsDao.setSetting('sms_throttle_delay_sec', _smsThrottleSecCtrl.text.trim());
    await db.settingsDao.setSetting('checkin_sms_template', _checkinSmsTemplateCtrl.text.trim());

    await db.settingsDao.setSetting('whatsapp_enabled', _waEnabled ? 'true' : 'false');
    await db.settingsDao.setSetting('twilio_account_sid', _twilioSidCtrl.text.trim());
    if (_twilioTokenCtrl.text.trim().isNotEmpty) {
      await db.settingsDao.setSetting('twilio_auth_token', _twilioTokenCtrl.text.trim());
    }
    await db.settingsDao.setSetting('twilio_from_phone', _twilioPhoneCtrl.text.trim());
    await db.settingsDao.setSetting('twilio_whatsapp_from', _twilioWaFromCtrl.text.trim());
    await db.settingsDao.setSetting('absence_sms_template', _smsTemplateCtrl.text.trim());
    await db.settingsDao.setSetting('absence_whatsapp_template', _waTemplateCtrl.text.trim());

    ref.invalidate(settingsMapProvider);

    // Dynamically notify bridge server of new device IP & port
    if (targetIp.isNotEmpty) {
      final client = ref.read(zkBackendClientProvider);
      client.connectDevice(targetIp, targetPort);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved and device configuration updated!')),
      );
    }
  }

  void _openTestSmsDialog() {
    final phoneCtrl = TextEditingController();
    final messageCtrl = TextEditingController(
      text: 'Test alert from ${_schoolNameCtrl.text.trim().isEmpty ? "School Portal" : _schoolNameCtrl.text.trim()}: SMS Gateway is connected and running!',
    );
    bool sending = false;
    String? statusMessage;
    bool isSuccess = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.sms_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Send Test SMS'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Test SMS dispatch via ${_smsProvider == "android_gateway" ? "Local Android Gateway (${_androidGatewayUrlCtrl.text.trim()})" : "Twilio Cloud Service"}.',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Recipient Phone Number',
                    hintText: '03001234567 or +923001234567',
                    prefixIcon: Icon(Icons.phone_android),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Message Body',
                  ),
                  maxLines: 2,
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSuccess
                          ? AppColors.present.withValues(alpha: 0.1)
                          : AppColors.absent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSuccess ? AppColors.present : AppColors.absent,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                          size: 18,
                          color: isSuccess ? AppColors.present : AppColors.absent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSuccess ? AppColors.present : AppColors.absent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              icon: sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, size: 16),
              label: Text(sending ? 'Sending...' : 'Send SMS'),
              onPressed: sending
                  ? null
                  : () async {
                      final to = phoneCtrl.text.trim();
                      final msg = messageCtrl.text.trim();
                      if (to.isEmpty || msg.isEmpty) {
                        setDialogState(() {
                          statusMessage = 'Please enter both phone number and message body.';
                          isSuccess = false;
                        });
                        return;
                      }

                      setDialogState(() {
                        sending = true;
                        statusMessage = null;
                      });

                      final gatewayProvider = ref.read(androidGatewayNotificationProvider);
                      final twilioProvider = ref.read(twilioNotificationProvider);

                      final credentials = <String, String>{
                        'sms_gateway_url': _androidGatewayUrlCtrl.text.trim(),
                        'sms_gateway_username': _androidGatewayUserCtrl.text.trim(),
                        'sms_gateway_password': _androidGatewayPassCtrl.text.trim(),
                        'twilio_account_sid': _twilioSidCtrl.text.trim(),
                        'twilio_auth_token': _twilioTokenCtrl.text.trim(),
                        'twilio_from_phone': _twilioPhoneCtrl.text.trim(),
                      };

                      final provider = _smsProvider == 'twilio' ? twilioProvider : gatewayProvider;
                      final res = await provider.sendSms(
                        to: to,
                        message: msg,
                        credentials: credentials,
                      );

                      setDialogState(() {
                        sending = false;
                        if (res.success) {
                          isSuccess = true;
                          statusMessage = 'Success! SMS sent. Message ID: ${res.messageId ?? "Dispatched via gateway"}';
                        } else {
                          isSuccess = false;
                          statusMessage = 'Failed to send: ${res.error ?? "Unknown error"}';
                        }
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedDemoData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dataset_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Populate Demo Data'),
          ],
        ),
        content: const SizedBox(
          width: 460,
          child: Text(
            'This will seed 16 demo students across 5 grade levels, 8 staff and teachers, today\'s attendance punches (present, late, absent), and parent alert jobs.\n\nExisting records will not be overwritten.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Proceed & Seed'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = ref.read(appDatabaseProvider);
    await DemoSeeder.seed(db);
    _initialized = false;
    ref.invalidate(settingsMapProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo school data populated successfully!'),
          backgroundColor: AppColors.present,
        ),
      );
    }
  }

  void _testBridge() async {
    final client = ref.read(zkBackendClientProvider);
    final targetIp = _k50IpCtrl.text.trim();
    final targetPort = int.tryParse(_k50PortCtrl.text.trim()) ?? 4370;

    // Proactively send configured IP to bridge
    if (targetIp.isNotEmpty) {
      await client.connectDevice(targetIp, targetPort);
    }

    final res = await client.health();

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                res.ok
                    ? (res.deviceOnline ? Icons.check_circle : Icons.warning_amber_rounded)
                    : Icons.error_outline,
                color: res.ok
                    ? (res.deviceOnline ? AppColors.present : AppColors.warning)
                    : AppColors.error,
              ),
              const SizedBox(width: 8),
              Text(
                !res.ok
                    ? 'Bridge Offline'
                    : (res.deviceOnline ? 'K50 Terminal Connected' : 'Bridge Running (Device Offline)'),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!res.ok)
                  Text(
                    'Could not connect to K50 bridge server on port ${_bridgePortCtrl.text}.\n\n'
                    'Error: ${res.error ?? "Connection refused."}\n\n'
                    'Make sure the bridge service is running.',
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  )
                else ...[
                  Text(
                    '• Bridge Server: RUNNING on port ${_bridgePortCtrl.text}\n'
                    '• Target Device IP: ${res.ip ?? targetIp}:${res.port ?? targetPort}\n'
                    '• Device Status: ${res.deviceOnline ? "ONLINE (Hardware Ready)" : "OFFLINE"}',
                    style: const TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  if (!res.deviceOnline) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Last Error: ${res.error ?? "Could not reach device"}\n\n'
                      'Troubleshooting:\n'
                      '1. Ensure device IP ($targetIp) is reachable (ping $targetIp)\n'
                      '2. Check ethernet cable / network switch\n'
                      '3. Verify port is set to 4370 in K50 device comm settings',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _loadBackups() async {
    if (!mounted) return;
    setState(() => _loadingBackups = true);
    try {
      final backupService = ref.read(databaseBackupServiceProvider);
      final list = await backupService.listBackups();
      if (mounted) {
        setState(() {
          _backups = list;
          _loadingBackups = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBackups = false);
    }
  }

  Future<void> _clearDummyData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.absent),
            SizedBox(width: 8),
            Text('Remove All Dummy / Test Data?'),
          ],
        ),
        content: const SizedBox(
          width: 480,
          child: Text(
            'This action will permanently delete all test/dummy students, enrollments, classes, sections, staff members, attendance logs, and notification records.\n\n'
            'Your System Administrator account (admin@school.local) and School Settings will be preserved so you can register real students and staff immediately.\n\n'
            'A safety backup of the database will be created before purging.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.absent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wipe All Dummy Data'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = ref.read(appDatabaseProvider);
    final backupService = ref.read(databaseBackupServiceProvider);

    // Create safety backup first
    try {
      await backupService.createBackup(db, tag: 'pre_purge');
    } catch (_) {}

    await DemoSeeder.clearDummyData(db);
    if (!mounted) return;
    await _loadBackups();
    if (!mounted) return;
    ref.invalidate(settingsMapProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All dummy students and demo staff cleared! Your classes, sections, and user records are preserved.'),
          backgroundColor: AppColors.present,
        ),
      );
    }
  }

  Future<void> _createBackupNow() async {
    final db = ref.read(appDatabaseProvider);
    final backupService = ref.read(databaseBackupServiceProvider);
    try {
      final item = await backupService.createBackup(db, tag: 'manual');
      if (!mounted) return;
      await _loadBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup created: ${item.fileName} (${item.formattedSize})'),
            backgroundColor: AppColors.present,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create backup: $e'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
    }
  }

  Future<void> _restoreBackup(BackupItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restore_page_outlined, color: AppColors.warning),
            SizedBox(width: 8),
            Text('Restore System from Backup?'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Text(
            'Are you sure you want to restore the system from:\n${item.fileName} (${item.formattedSize}, created ${item.formattedDate})?\n\n'
            'This will restore your complete database and all student/staff profile pictures.\n\n'
            'An emergency safety backup of current data will be made automatically before restoring.',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Proceed with Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = ref.read(appDatabaseProvider);
    final backupService = ref.read(databaseBackupServiceProvider);

    try {
      await backupService.restoreBackup(db, File(item.filePath));
      if (!mounted) return;
      await _loadBackups();
      if (!mounted) return;
      ref.invalidate(settingsMapProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database successfully restored! Please restart the application if needed.'),
            backgroundColor: AppColors.present,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: $e'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
    }
  }

  Future<void> _checkIntegrity() async {
    final db = ref.read(appDatabaseProvider);
    final backupService = ref.read(databaseBackupServiceProvider);
    final res = await backupService.checkIntegrity(db);
    setState(() => _integrityStatus = res);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res == 'ok'
              ? 'SQLite Database Integrity Check: PASSED (Database healthy)'
              : 'SQLite Integrity Check Result: $res'),
          backgroundColor: res == 'ok' ? AppColors.present : AppColors.absent,
        ),
      );
    }
  }

  Future<void> _openBackupFolder() async {
    final backupService = ref.read(databaseBackupServiceProvider);
    try {
      await backupService.openBackupFolder();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open folder: $e'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
    }
  }
}
