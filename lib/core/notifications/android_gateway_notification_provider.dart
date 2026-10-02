import 'dart:convert';
import 'package:http/http.dart' as http;
import 'notification_provider.dart';

/// Sends SMS alerts locally via an Android phone running an SMS Gateway app
/// (e.g., "SMS Gateway for Android" by capcom6, Textbee, or local web server).
///
/// This eliminates recurring cloud SMS charges (Twilio/Infobip) by leveraging
/// low-cost local SIM bundles (Jazz, Zong, Telenor, Ufone).
class AndroidGatewayNotificationProvider implements NotificationProvider {
  AndroidGatewayNotificationProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'android_gateway';

  @override
  Future<NotificationSendResult> sendSms({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    final rawUrl = credentials['sms_gateway_url']?.trim() ?? '';
    final username = credentials['sms_gateway_username']?.trim() ?? '';
    final password = credentials['sms_gateway_password']?.trim() ?? '';
    final token = credentials['sms_gateway_token']?.trim() ?? '';

    if (rawUrl.isEmpty) {
      return const NotificationSendResult(
        success: false,
        error: 'Android SMS Gateway URL is not configured (e.g. http://192.168.18.50:8080).',
      );
    }

    // Format clean target URL
    Uri targetUri;
    try {
      final base = rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
          ? rawUrl
          : 'http://$rawUrl';
      final parsed = Uri.parse(base);
      if (parsed.path.isEmpty || parsed.path == '/') {
        // Standard endpoint for "SMS Gateway for Android" (capcom6)
        targetUri = parsed.replace(path: '/message');
      } else {
        targetUri = parsed;
      }
    } catch (e) {
      return NotificationSendResult(
        success: false,
        error: 'Invalid Gateway URL format "$rawUrl": $e',
      );
    }

    // Clean phone number: preserve leading + or convert standard format
    final cleanPhone = to.trim().replaceAll(RegExp(r'[\s\-()]'), '');

    // Dual-compatible payload: works with Capcom6, Textbee, and generic SMS apps
    final payload = jsonEncode({
      'phoneNumbers': [cleanPhone],
      'message': message,
      'to': cleanPhone,
      'text': message,
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else if (username.isNotEmpty || password.isNotEmpty) {
      final authStr = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $authStr';
    }

    try {
      final res = await _client
          .post(targetUri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        String? msgId;
        try {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          msgId = data['id']?.toString() ?? data['messageId']?.toString();
        } catch (_) {}
        return NotificationSendResult(
          success: true,
          messageId: msgId,
          rawResponse: res.body,
        );
      } else {
        return NotificationSendResult(
          success: false,
          error: 'Android Gateway error HTTP ${res.statusCode}: ${res.body}',
          rawResponse: res.body,
        );
      }
    } catch (e) {
      return NotificationSendResult(
        success: false,
        error: 'Cannot connect to Android phone at $targetUri. '
            'Ensure the phone is on the same Wi-Fi, the SMS Gateway app is open, and battery optimization is disabled: $e',
      );
    }
  }

  @override
  Future<NotificationSendResult> sendWhatsApp({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    // Android local gateway is dedicated to native GSM SMS
    return const NotificationSendResult(
      success: false,
      error: 'WhatsApp dispatch is not supported via local Android GSM gateway. Use Twilio provider for WhatsApp.',
    );
  }
}
