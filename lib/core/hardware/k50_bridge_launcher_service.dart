import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Ensures K50Bridge is running when the School Attendance Portal opens (Windows PC).
class K50BridgeLauncherService {
  K50BridgeLauncherService({this.installDir});

  final String? installDir;

  static const defaultInstallDir = r'C:\Program Files\School Attendance Portal';

  bool _ensureInFlight = false;

  Future<void> ensureRunning({
    required List<String> bridgeUrls,
    String? deviceIp,
    int? devicePort,
  }) async {
    if (!Platform.isWindows || bridgeUrls.isEmpty) return;
    if (_ensureInFlight) return;

    _ensureInFlight = true;
    try {
      final anyUp = await _anyBridgeUp(bridgeUrls);
      if (!anyUp) {
        await _startInstalledBridges();
      }

      await Future.wait(
        bridgeUrls.map((url) => _waitForBridge(url, const Duration(seconds: 45))),
      );

      await _connectDevices(bridgeUrls, deviceIp: deviceIp, devicePort: devicePort);
    } finally {
      _ensureInFlight = false;
    }
  }

  Future<bool> _anyBridgeUp(List<String> urls) async {
    for (final url in urls) {
      if (await _isBridgeProcessUp(url)) return true;
    }
    return false;
  }

  Future<bool> _isBridgeProcessUp(String baseUrl) async {
    try {
      final uri = _healthUri(baseUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) return false;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['bridgeUp'] == true;
    } catch (_) {
      return false;
    }
  }

  Uri _healthUri(String baseUrl) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized/health');
  }

  Uri _connectUri(String baseUrl) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized/device/connect');
  }

  Future<void> _startInstalledBridges() async {
    final root = installDir ?? defaultInstallDir;
    final allCmd = File('$root\\start-all-k50-bridges.cmd');
    if (allCmd.existsSync()) {
      await Process.start('cmd.exe', ['/c', allCmd.path], runInShell: false);
      return;
    }

    final cmd = File('$root\\K50Bridge\\start-k50-bridge.cmd');
    if (cmd.existsSync()) {
      await Process.start('cmd.exe', ['/c', cmd.path], runInShell: false);
    }
  }

  Future<void> _waitForBridge(String url, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isBridgeProcessUp(url)) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _connectDevices(
    List<String> urls, {
    String? deviceIp,
    int? devicePort,
  }) async {
    for (final url in urls) {
      if (!await _isBridgeProcessUp(url)) continue;
      try {
        final payload = <String, dynamic>{};
        if (deviceIp != null && deviceIp.isNotEmpty) {
          payload['ip'] = deviceIp;
        }
        if (devicePort != null && devicePort > 0) {
          payload['port'] = devicePort;
        }
        await http
            .post(
              _connectUri(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 20));
      } catch (_) {}
    }
  }
}
