class NotificationSendResult {
  const NotificationSendResult({
    required this.success,
    this.messageId,
    this.error,
    this.rawResponse,
  });

  final bool success;
  final String? messageId;
  final String? error;
  final String? rawResponse;
}

abstract class NotificationProvider {
  String get name;

  Future<NotificationSendResult> sendSms({
    required String to,
    required String message,
    required Map<String, String> credentials,
  });

  Future<NotificationSendResult> sendWhatsApp({
    required String to,
    required String message,
    required Map<String, String> credentials,
  });
}
