import 'dart:convert';
import 'package:http/http.dart' as http;
import 'notification_provider.dart';

class TwilioNotificationProvider implements NotificationProvider {
  TwilioNotificationProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'twilio';

  @override
  Future<NotificationSendResult> sendSms({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    final accountSid = credentials['twilio_account_sid']?.trim() ?? '';
    final authToken = credentials['twilio_auth_token']?.trim() ?? '';
    final fromPhone = credentials['twilio_from_phone']?.trim() ?? '';

    if (accountSid.isEmpty || authToken.isEmpty || fromPhone.isEmpty) {
      return const NotificationSendResult(
        success: false,
        error: 'Twilio SMS credentials (SID, Token, or From Phone) are not configured.',
      );
    }

    final url = Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json');
    final authHeader = 'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}';

    try {
      final res = await _client.post(
        url,
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'From': fromPhone,
          'To': to,
          'Body': message,
        },
      ).timeout(const Duration(seconds: 15));

      final body = res.body;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return NotificationSendResult(
          success: true,
          messageId: json['sid'] as String?,
          rawResponse: body,
        );
      } else {
        return NotificationSendResult(
          success: false,
          error: 'Twilio error HTTP ${res.statusCode}: $body',
          rawResponse: body,
        );
      }
    } catch (e) {
      return NotificationSendResult(success: false, error: e.toString());
    }
  }

  @override
  Future<NotificationSendResult> sendWhatsApp({
    required String to,
    required String message,
    required Map<String, String> credentials,
  }) async {
    final accountSid = credentials['twilio_account_sid']?.trim() ?? '';
    final authToken = credentials['twilio_auth_token']?.trim() ?? '';
    final fromNumber = credentials['twilio_whatsapp_from']?.trim() ?? '';

    if (accountSid.isEmpty || authToken.isEmpty || fromNumber.isEmpty) {
      return const NotificationSendResult(
        success: false,
        error: 'Twilio WhatsApp credentials (SID, Token, or WhatsApp From) are not configured.',
      );
    }

    final formattedFrom = fromNumber.startsWith('whatsapp:') ? fromNumber : 'whatsapp:$fromNumber';
    final formattedTo = to.startsWith('whatsapp:') ? to : 'whatsapp:$to';

    final url = Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json');
    final authHeader = 'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}';

    try {
      final res = await _client.post(
        url,
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'From': formattedFrom,
          'To': formattedTo,
          'Body': message,
        },
      ).timeout(const Duration(seconds: 15));

      final body = res.body;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return NotificationSendResult(
          success: true,
          messageId: json['sid'] as String?,
          rawResponse: body,
        );
      } else {
        return NotificationSendResult(
          success: false,
          error: 'Twilio WhatsApp error HTTP ${res.statusCode}: $body',
          rawResponse: body,
        );
      }
    } catch (e) {
      return NotificationSendResult(success: false, error: e.toString());
    }
  }
}
