/// Raw log entry from the K50 biometric device or bridge.
class LogEntry {
  const LogEntry({
    required this.userId,
    required this.timestamp,
    required this.verifyType,
    this.deviceUserId,
  });

  final String userId;
  final DateTime timestamp;
  final int verifyType;
  final String? deviceUserId;
}

class UserTemplate {
  const UserTemplate({
    required this.userId,
    required this.name,
    required this.template,
    required this.enabled,
    this.password = '',
  });

  final String userId;
  final String name;
  final String template;
  final bool enabled;
  final String password;
}

class EnrollResult {
  const EnrollResult.success(this.templateId)
      : error = null,
        success = true;

  const EnrollResult.failure(this.error)
      : templateId = null,
        success = false;

  final bool success;
  final String? templateId;
  final String? error;
}

abstract class ZKDeviceService {
  String? get lastError;

  Future<bool> connect(String ip, int port);

  Future<EnrollResult> enrollFingerprint(String userId, String userType);

  Future<bool> deleteFingerprint(String userId);

  Future<bool> enableUser(String userId, {String? name});

  Future<bool> disableUser(String userId, {String? name});

  Future<bool> deleteUser(String userId);

  Future<List<LogEntry>> pullAttendanceLogs();

  Future<bool> pushUser(UserTemplate user);

  Future<bool> pushAllUsers(List<UserTemplate> users);
}
