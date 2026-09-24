import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'zk_device_service.dart';

/// Subscribes to real-time attendance pushes from K50 bridge WebSocket endpoints.
class K50AttendancePushService {
  K50AttendancePushService({required this.onLog});

  final void Function(LogEntry log) onLog;

  bool _stopped = true;
  final Map<String, _BridgeConnection> _connections = {};

  void start(List<String> httpBaseUrls) {
    _stopped = false;
    final targets = httpBaseUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toSet();

    for (final url in targets) {
      _connections.putIfAbsent(url, () => _BridgeConnection(url));
    }

    for (final removed
        in _connections.keys.where((k) => !targets.contains(k)).toList()) {
      _connections.remove(removed)?.dispose();
    }

    for (final connection in _connections.values) {
      connection.connectIfNeeded(this);
    }
  }

  void stop() {
    _stopped = true;
    for (final connection in _connections.values) {
      connection.dispose();
    }
    _connections.clear();
  }

  bool get isActive => !_stopped;

  void _scheduleReconnect(_BridgeConnection connection) {
    if (_stopped) return;
    connection.scheduleReconnect(() {
      if (_stopped) return;
      connection.connectIfNeeded(this);
    });
  }

  void _handleMessage(String baseUrl, dynamic data) {
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['type'] != 'attendance') return;

      final logMap = json['log'] as Map<String, dynamic>?;
      if (logMap == null) return;

      final log = LogEntry(
        userId: logMap['userId'] as String? ?? '',
        deviceUserId: logMap['deviceUserId'] as String?,
        timestamp: DateTime.parse(logMap['timestamp'] as String),
        verifyType: logMap['verifyType'] as int? ?? 1,
      );
      onLog(log);
    } catch (e, st) {
      developer.log(
        'K50 attendance push parse failed ($baseUrl)',
        name: 'K50AttendancePushService',
        error: e,
        stackTrace: st,
      );
    }
  }

  static Uri _toWsUri(String httpBaseUrl) {
    final uri = Uri.parse(httpBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.port,
      path: '/device/attendance/ws',
    );
  }
}

class _BridgeConnection {
  _BridgeConnection(this.baseUrl);

  final String baseUrl;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _attempt = 0;

  void connectIfNeeded(K50AttendancePushService owner) {
    if (_socket != null || _reconnectTimer != null) return;
    _connect(owner);
  }

  void _connect(K50AttendancePushService owner) {
    final wsUri = K50AttendancePushService._toWsUri(baseUrl);
    WebSocket.connect(wsUri.toString()).then((socket) {
      if (owner._stopped) {
        socket.close();
        return;
      }

      _socket = socket;
      _attempt = 0;
      developer.log('Connected to $wsUri', name: 'K50AttendancePushService');

      _subscription = socket.listen(
        (data) => owner._handleMessage(baseUrl, data),
        onDone: () {
          _clearSocket();
          owner._scheduleReconnect(this);
        },
        onError: (_) {
          _clearSocket();
          owner._scheduleReconnect(this);
        },
        cancelOnError: true,
      );
    }).catchError((Object e) {
      developer.log(
        'WebSocket connect failed ($wsUri): $e',
        name: 'K50AttendancePushService',
      );
      owner._scheduleReconnect(this);
    });
  }

  void scheduleReconnect(void Function() reconnect) {
    _clearSocket();
    if (_reconnectTimer != null) return;

    _attempt++;
    final delay = Duration(seconds: _attempt.clamp(1, 30));
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      reconnect();
    });
  }

  void _clearSocket() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _clearSocket();
  }
}
