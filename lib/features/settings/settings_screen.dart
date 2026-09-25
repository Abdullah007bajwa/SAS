import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_provider.dart';
import '../../core/database/demo_seeder.dart';
import '../../core/hardware/hardware_providers.dart';
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

  bool _smsEnabled = false;
  bool _waEnabled = false;
  bool _initialized = false;

  void _populate(Map<String, String> s) {
    if (_initialized) return;
    _initialized = true;

    _schoolNameCtrl.text = s['school_name'] ?? 'School Attendance Portal';
    _cutoffTimeCtrl.text = s['student_cutoff_time'] ?? '08:30';
    _gracePeriodCtrl.text = s['attendance_grace_period'] ?? '15';
    _studentStartCtrl.text = s['student_id_range_start'] ?? '1001';
    _studentEndCtrl.text = s['student_id_range_end'] ?? '7999';
    _staffStartCtrl.text = s['staff_id_range_start'] ?? '8001';
    _staffEndCtrl.text = s['staff_id_range_end'] ?? '8999';
    _k50IpCtrl.text = s['k50_ip'] ?? '192.168.1.201';
    _k50PortCtrl.text = s['k50_port'] ?? '4370';
    _bridgePortCtrl.text = s['k50_bridge_port'] ?? '8787';

    _smsEnabled = s['sms_enabled'] == 'true';
    _waEnabled = s['whatsapp_enabled'] == 'true';
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.dataset_outlined, size: 16),
                        label: const Text('Seed Demo Data'),
                        onPressed: _seedDemoData,
                      ),
                      const SizedBox(width: 12),
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
                                labelText: 'Student Cutoff Time (HH:mm)',
                                hintText: '08:30',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _gracePeriodCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Teacher Grace Period (minutes)',
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

              // Section 4: Parent Absence Notifications (Twilio)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 20),
                          SizedBox(width: 8),
                          Text('Parent Absence Alert Service (Twilio)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Enable SMS Notifications'),
                              subtitle: const Text('Send SMS text alert to parent on cutoff absence'),
                              value: _smsEnabled,
                              onChanged: (val) => setState(() => _smsEnabled = val),
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Enable WhatsApp Alerts'),
                              subtitle: const Text('Send WhatsApp message to parent on cutoff absence'),
                              value: _waEnabled,
                              onChanged: (val) => setState(() => _waEnabled = val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                              decoration: const InputDecoration(labelText: 'Twilio Sender Phone (SMS)', hintText: '+1234567890'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _twilioWaFromCtrl,
                              decoration: const InputDecoration(labelText: 'Twilio WhatsApp Sender', hintText: '+14155238886'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _smsTemplateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Absence SMS Template',
                          helperText: 'Available placeholders: {student_name}, {date}',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _waTemplateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Absence WhatsApp Template',
                          helperText: 'Available placeholders: {student_name}, {date}',
                        ),
                        maxLines: 2,
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
    await db.settingsDao.setSetting('attendance_grace_period', _gracePeriodCtrl.text.trim());
    await db.settingsDao.setSetting('student_id_range_start', _studentStartCtrl.text.trim());
    await db.settingsDao.setSetting('student_id_range_end', _studentEndCtrl.text.trim());
    await db.settingsDao.setSetting('staff_id_range_start', _staffStartCtrl.text.trim());
    await db.settingsDao.setSetting('staff_id_range_end', _staffEndCtrl.text.trim());
    await db.settingsDao.setSetting('k50_ip', _k50IpCtrl.text.trim());
    await db.settingsDao.setSetting('k50_port', _k50PortCtrl.text.trim());
    await db.settingsDao.setSetting('k50_bridge_port', _bridgePortCtrl.text.trim());

    await db.settingsDao.setSetting('sms_enabled', _smsEnabled ? 'true' : 'false');
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
    }
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
    final res = await client.health();

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                res.ok ? Icons.check_circle : Icons.error_outline,
                color: res.ok ? AppColors.present : AppColors.error,
              ),
              const SizedBox(width: 8),
              Text(res.ok ? 'Bridge Connected' : 'Bridge Offline'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Text(
              res.ok
                  ? 'The C# K50 bridge is running and responsive on port ${_bridgePortCtrl.text}.\nDevice online: ${res.deviceOnline ? "Yes" : "No"}'
                  : 'Could not connect to C# bridge: ${res.error ?? "Connection refused."}\n\nMake sure K50Bridge is running on Windows (or configured host).',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }
}
