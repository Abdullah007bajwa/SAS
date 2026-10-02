
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_provider.dart';
import '../../core/hardware/hardware_providers.dart';
import '../../core/hardware/k50_status_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../utils/id_generator.dart';

enum EnrollPhase {
  ready,
  commandSent,
  waitingFinger,
  success,
  failed,
}

class K50EnrollDialog extends ConsumerStatefulWidget {
  const K50EnrollDialog({
    super.key,
    required this.personType,
    required this.personId,
    required this.personCode,
    required this.personName,
    this.existingFingerprintId,
    this.overrideDeviceUserId,
    this.onEnrollmentSuccess,
  });

  final String personType; // 'student' or 'staff'
  final int personId;
  final String personCode;
  final String personName;
  final String? existingFingerprintId;
  final String? overrideDeviceUserId;
  final VoidCallback? onEnrollmentSuccess;

  static Future<void> show(
    BuildContext context, {
    required String personType,
    required int personId,
    required String personCode,
    required String personName,
    String? existingFingerprintId,
    String? overrideDeviceUserId,
    VoidCallback? onEnrollmentSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => K50EnrollDialog(
        personType: personType,
        personId: personId,
        personCode: personCode,
        personName: personName,
        existingFingerprintId: existingFingerprintId,
        overrideDeviceUserId: overrideDeviceUserId,
        onEnrollmentSuccess: onEnrollmentSuccess,
      ),
    );
  }

  @override
  ConsumerState<K50EnrollDialog> createState() => _K50EnrollDialogState();
}

class _K50EnrollDialogState extends ConsumerState<K50EnrollDialog> {
  EnrollPhase _phase = EnrollPhase.ready;
  String? _statusMessage;
  String? _errorMessage;
  int _secondsRemaining = 35;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  int _selectedFingerIndex = 0; // 0 = right thumb, 1 = right index, etc.

  final List<String> _fingerNames = [
    'Right Thumb (Default)',
    'Right Index Finger',
    'Right Middle Finger',
    'Left Thumb',
    'Left Index Finger',
  ];

  /// The K50 firmware strictly requires numeric IDs (1 - 99999999).
  /// Students map to 1001-7999 (or class-aware e.g. 3117, 10118), staff to 8001-8999.
  String get _numericDeviceUserId {
    if (widget.overrideDeviceUserId != null && widget.overrideDeviceUserId!.trim().isNotEmpty) {
      return widget.overrideDeviceUserId!.trim();
    }

    // Check remembered mapping in SharedPreferences
    final mappedDevice = ref.read(k50DeviceUserMapProvider).deviceUserIdForPersonCode(widget.personCode);
    if (mappedDevice != null && mappedDevice.isNotEmpty) {
      return mappedDevice;
    }

    // Check existing fingerprint ID: e.g. FP-3117 -> 3117
    if (widget.existingFingerprintId != null) {
      final fpDigits = IdGenerator.extractNumeric(widget.existingFingerprintId!);
      if (fpDigits != null && fpDigits.isNotEmpty) return fpDigits;
    }

    // Check class-aware code format: e.g. C3A-017 or C10A-018
    final classAwareMatch = RegExp(r'^[A-Za-z]+(\d+)([A-Za-z]+)-?(\d+)$').firstMatch(widget.personCode.trim());
    if (classAwareMatch != null) {
      final classLvl = int.tryParse(classAwareMatch.group(1)!) ?? 1;
      final secLetter = classAwareMatch.group(2)!;
      final seq = int.tryParse(classAwareMatch.group(3)!) ?? 1;
      final autoId = IdGenerator.generateClassAwareBiometricId(
        classLevel: classLvl,
        sectionName: secLetter,
        sequence: seq,
      );
      return '$autoId';
    }

    final rawDigits = IdGenerator.extractNumeric(widget.personCode);
    final parsed = int.tryParse(rawDigits ?? '');

    if (widget.personType == 'student') {
      if (parsed != null && parsed >= 1000) return '$parsed';
      return '${1000 + widget.personId}';
    } else {
      // Staff & Teachers: partitioned in 8000+ range
      if (parsed != null && parsed >= 8000) return '$parsed';
      return '${8000 + (parsed ?? widget.personId)}';
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startEnrollment() async {
    final deviceId = _numericDeviceUserId;

    setState(() {
      _phase = EnrollPhase.commandSent;
      _statusMessage = 'Sending enroll command to K50 for Numeric ID $deviceId...';
      _errorMessage = null;
      _secondsRemaining = 50;
    });

    final client = ref.read(zkBackendClientProvider);
    final userMap = ref.read(k50DeviceUserMapProvider);
    final k50State = ref.read(k50StatusProvider);

    // Ensure mapping exists before enroll starts
    await userMap.remember(deviceId, widget.personCode);

    try {
      // Send purely numeric device ID to the K50 bridge
      final res = await client.startEnroll(
        appUserId: deviceId,
        name: widget.personName,
        fingerIndex: _selectedFingerIndex,
      );

      if (res.success && (res.verified || res.templateId != null)) {
        await _saveEnrollment(res.templateId ?? 'FP-$deviceId');
        return;
      }

      if (!res.success && !res.requiresOnDevice && !res.remoteModeStarted && k50State.state == K50ConnectionState.connected) {
        setState(() {
          _phase = EnrollPhase.failed;
          _errorMessage = res.error ?? 'K50 rejected enroll command';
        });
        return;
      }

      // Transition to waiting for student/teacher to press thumb 3 times
      setState(() {
        _phase = EnrollPhase.waitingFinger;
        _statusMessage = 'K50 terminal has entered enroll mode for User ID $deviceId.\nPlace thumb on optical sensor 3 times.';
      });

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_secondsRemaining <= 1) {
          t.cancel();
          _pollTimer?.cancel();
          setState(() {
            _phase = EnrollPhase.failed;
            _errorMessage = 'Enrollment timed out waiting for finger scan on K50';
          });
        } else {
          setState(() {
            _secondsRemaining--;
          });
        }
      });

      _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (t) async {
        if (!mounted || _phase != EnrollPhase.waitingFinger) {
          t.cancel();
          return;
        }

        try {
          final poll = await client.pollEnroll(deviceId);
          if (!mounted) return;

          if (poll.success && (poll.verified || poll.templateId != null)) {
            t.cancel();
            _countdownTimer?.cancel();
            await _saveEnrollment(poll.templateId ?? 'FP-$deviceId');
          }
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = EnrollPhase.failed;
        _errorMessage = 'Could not contact K50 bridge: $e';
      });
    }
  }

  Future<void> _checkVerificationNow() async {
    final client = ref.read(zkBackendClientProvider);
    final deviceId = _numericDeviceUserId;
    try {
      final poll = await client.verifyFingerprint(deviceId);
      if (!mounted) return;
      if (poll.success && (poll.verified || poll.templateId != null)) {
        _countdownTimer?.cancel();
        _pollTimer?.cancel();
        await _saveEnrollment(poll.templateId ?? 'FP-$deviceId');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('K50 has not recorded 3 finger presses yet. Please complete thumb scan on scanner.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bridge query failed: $e')),
      );
    }
  }

  Future<void> _saveEnrollment(String templateId) async {
    final db = ref.read(appDatabaseProvider);
    final userMap = ref.read(k50DeviceUserMapProvider);
    final deviceId = _numericDeviceUserId;

    await userMap.remember(deviceId, widget.personCode);

    if (widget.personType == 'student') {
      await db.studentsDao.updateStudent(
        widget.personId,
        fingerprintId: templateId,
      );
    } else {
      await db.staffDao.updateStaff(
        widget.personId,
        fingerprintId: templateId,
      );
    }

    if (!mounted) return;

    setState(() {
      _phase = EnrollPhase.success;
      _statusMessage = 'Biometric template registered under Numeric ID $deviceId!';
    });

    widget.onEnrollmentSuccess?.call();
  }

  void _simulateHardwareEnrollment() async {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    await _saveEnrollment('FP-$_numericDeviceUserId-${DateTime.now().millisecondsSinceEpoch % 10000}');
  }

  @override
  Widget build(BuildContext context) {
    final k50Status = ref.watch(k50StatusProvider);
    final deviceId = _numericDeviceUserId;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.fingerprint, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enroll Biometric Fingerprint',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${widget.personType.toUpperCase()}: ${widget.personName} (${widget.personCode})',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHardwareBanner(k50Status),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('App Person Code:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        Text(widget.personCode, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.pin, size: 16, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text('K50 Hardware Numeric ID:', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            deviceId,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '* K50 firmware strictly requires numeric digits (0-9). The terminal displays this ID.',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                      ),
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Select Finger:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        DropdownButton<int>(
                          value: _selectedFingerIndex,
                          isDense: true,
                          underline: const SizedBox(),
                          items: List.generate(_fingerNames.length, (i) {
                            return DropdownMenuItem(value: i, child: Text(_fingerNames[i], style: const TextStyle(fontSize: 12)));
                          }),
                          onChanged: _phase == EnrollPhase.ready ? (val) {
                            if (val != null) setState(() => _selectedFingerIndex = val);
                          } : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _buildPhaseContent(k50Status, deviceId),
            ],
          ),
        ),
      ),
      actions: [
        if (_phase == EnrollPhase.ready || _phase == EnrollPhase.failed) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            label: Text('Send Enroll Command ($deviceId)'),
            onPressed: _startEnrollment,
          ),
        ] else if (_phase == EnrollPhase.waitingFinger) ...[
          TextButton(
            onPressed: () {
              _countdownTimer?.cancel();
              _pollTimer?.cancel();
              setState(() => _phase = EnrollPhase.ready);
            },
            child: const Text('Cancel Scan'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Confirm / Verify Scan'),
            onPressed: _checkVerificationNow,
          ),
          Tooltip(
            message: 'Simulates finger press ACK for development environments',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.fact_check, size: 16),
              label: const Text('Simulate ACK'),
              onPressed: _simulateHardwareEnrollment,
            ),
          ),
        ] else if (_phase == EnrollPhase.success) ...[
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ],
    );
  }

  Widget _buildHardwareBanner(K50Status k50Status) {
    Color bg;
    Color border;
    IconData icon;
    String title;
    String sub;

    switch (k50Status.state) {
      case K50ConnectionState.connected:
        bg = AppColors.present.withValues(alpha: 0.1);
        border = AppColors.present.withValues(alpha: 0.3);
        icon = Icons.check_circle_outline;
        title = 'K50 Terminal Ready (${k50Status.ip ?? "Connected"}:4370)';
        sub = 'Device is online. Ready to initiate 3-step biometric fingerprint capture.';
        break;
      case K50ConnectionState.bridgeOnly:
        bg = AppColors.late.withValues(alpha: 0.1);
        border = AppColors.late.withValues(alpha: 0.3);
        icon = Icons.warning_amber_rounded;
        title = 'K50 Bridge Active (Reader Offline)';
        sub = 'Bridge is listening on port 8787, but reader cable is disconnected. Simulation mode available.';
        break;
      case K50ConnectionState.offline:
        bg = AppColors.absent.withValues(alpha: 0.1);
        border = AppColors.absent.withValues(alpha: 0.3);
        icon = Icons.error_outline;
        title = 'K50 Bridge Disconnected (Offline)';
        sub = 'Start the K50 Bridge service on port 8787. You can test in simulation mode.';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: border, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary)),
                Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseContent(K50Status k50Status, String deviceId) {
    switch (_phase) {
      case EnrollPhase.ready:
        return Center(
          child: Column(
            children: [
              const Icon(Icons.touch_app_outlined, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 8),
              Text(
                'Click "Send Enroll Command" below.\nThe K50 will allocate User ID $deviceId and prompt:\n"Please press your finger 3 times".',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        );

      case EnrollPhase.commandSent:
        return Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                'Sending User ID $deviceId to K50 hardware...',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );

      case EnrollPhase.waitingFinger:
        return Center(
          child: Column(
            children: [
              const Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  Icon(Icons.fingerprint, size: 36, color: AppColors.primary),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _statusMessage ?? 'Place finger on K50 reader now',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'Time remaining: $_secondsRemaining seconds',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        );

      case EnrollPhase.success:
        return Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.present,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 36, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage ?? 'Enrolled successfully!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.present),
              ),
            ],
          ),
        );

      case EnrollPhase.failed:
        return Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.absent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 36, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Enrollment failed or timed out',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.absent),
              ),
              const SizedBox(height: 4),
              const Text(
                'Check that the K50 reader is online and try again.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
    }
  }
}
