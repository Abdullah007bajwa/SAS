import 'dart:convert';
import 'package:http/http.dart' as http;

import 'zk_device_service.dart';

class BackendApiException implements Exception {
  BackendApiException(this.message, {this.errorCode, this.retryAfter});

  final String message;
  final String? errorCode;
  final int? retryAfter;

  @override
  String toString() => message;
}

class BackendEnrollResponse {
  const BackendEnrollResponse({
    required this.success,
    this.error,
    this.errorCode,
    this.templateId,
    this.requiresOnDevice = false,
    this.remoteModeStarted = false,
    this.deviceUserId,
    this.enrollState,
    this.verified = false,
  });

  factory BackendEnrollResponse.fromJson(Map<String, dynamic> json) {
    return BackendEnrollResponse(
      success: json['success'] == true,
      error: json['error'] as String?,
      errorCode: json['errorCode'] as String?,
      templateId: json['templateId'] as String?,
      requiresOnDevice: json['requiresOnDevice'] == true,
      remoteModeStarted: json['remoteModeStarted'] == true,
      deviceUserId: json['deviceUserId'] as String?,
      enrollState: json['enrollState'] as String?,
      verified: json['verified'] == true,
    );
  }

  final bool success;
  final String? error;
  final String? errorCode;
  final String? templateId;
  final bool requiresOnDevice;
  final bool remoteModeStarted;
  final String? deviceUserId;
  final String? enrollState;
  final bool verified;
}

class BackendHealthResponse {
  const BackendHealthResponse({
    required this.ok,
    this.deviceOnline = false,
    this.deviceState,
    this.ip,
    this.error,
    this.queuePending,
    this.queueBusy,
  });

  factory BackendHealthResponse.fromJson(Map<String, dynamic> json) {
    return BackendHealthResponse(
      ok: json['bridgeUp'] == true,
      deviceOnline: json['ok'] == true,
      deviceState: json['deviceState'] as String?,
      ip: json['ip'] as String?,
      error: json['lastError'] as String? ?? json['error'] as String?,
      queuePending: json['queuePending'] as int?,
      queueBusy: json['queueBusy'] as bool?,
    );
  }

  final bool ok;
  final bool deviceOnline;
  final String? deviceState;
  final String? ip;
  final String? error;
  final int? queuePending;
  final bool? queueBusy;
}

class ZkBackendClient {
  ZkBackendClient({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  String _cleanUrl(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  Future<BackendHealthResponse> health() async {
    try {
      final res = await _client.get(Uri.parse(_cleanUrl('/health'))).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return BackendHealthResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return BackendHealthResponse(ok: false, error: 'HTTP ${res.statusCode}');
    } catch (e) {
      return BackendHealthResponse(ok: false, error: e.toString());
    }
  }

  Future<bool> connectDevice(String ip, int port) async {
    try {
      final res = await _client.post(
        Uri.parse(_cleanUrl('/device/connect')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ip': ip, 'port': port}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return json['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<LogEntry>> pullAttendanceLogs() async {
    try {
      final res = await _client.get(
        Uri.parse(_cleanUrl('/device/attendance')),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List<dynamic>;

      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return LogEntry(
          userId: m['userId'] as String? ?? '',
          deviceUserId: m['deviceUserId'] as String?,
          timestamp: DateTime.parse(m['timestamp'] as String),
          verifyType: m['verifyType'] as int? ?? 1,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<BackendEnrollResponse> startEnroll({
    required String appUserId,
    required String name,
    int? fingerIndex,
    int timeoutSec = 45,
  }) async {
    try {
      final res = await _client.post(
        Uri.parse(_cleanUrl('/device/fingerprint/enroll')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': appUserId,
          'name': name,
          'fingerIndex': fingerIndex ?? 0,
          'timeoutSec': timeoutSec,
        }),
      ).timeout(Duration(seconds: timeoutSec + 15));

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return BackendEnrollResponse.fromJson(json);
    } catch (e) {
      return BackendEnrollResponse(success: false, error: e.toString());
    }
  }

  Future<BackendEnrollResponse> verifyFingerprint(String appUserId) async {
    try {
      final res = await _client.post(
        Uri.parse(_cleanUrl('/device/fingerprint/verify')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': appUserId}),
      ).timeout(const Duration(seconds: 10));

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return BackendEnrollResponse.fromJson(json);
    } catch (e) {
      return BackendEnrollResponse(success: false, error: e.toString());
    }
  }

  Future<BackendEnrollResponse> pollEnroll(String appUserId) async {
    return verifyFingerprint(appUserId);
  }

  Future<bool> deleteUser(String appUserId) async {
    try {
      final res = await _client.post(
        Uri.parse(_cleanUrl('/device/user/delete')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': appUserId}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return json['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
