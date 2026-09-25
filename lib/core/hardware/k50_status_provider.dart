import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hardware_providers.dart';
import 'zk_backend_client.dart';

enum K50ConnectionState {
  offline,       // Bridge unreachable / down
  bridgeOnly,    // Bridge running, K50 biometric reader offline
  connected,     // Both Bridge and K50 biometric reader online
}

class K50Status {
  final K50ConnectionState state;
  final String label;
  final String details;
  final DateTime lastChecked;
  final String? ip;

  const K50Status({
    required this.state,
    required this.label,
    required this.details,
    required this.lastChecked,
    this.ip,
  });

  bool get isFullyOnline => state == K50ConnectionState.connected;
  bool get isBridgeUp => state != K50ConnectionState.offline;
}

class K50StatusNotifier extends StateNotifier<K50Status> {
  K50StatusNotifier(this._client)
      : super(K50Status(
          state: K50ConnectionState.offline,
          label: 'K50 Disconnected',
          details: 'Bridge service is not responding at http://127.0.0.1:8787',
          lastChecked: DateTime.now(),
        )) {
    checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => checkStatus());
  }

  final ZkBackendClient _client;
  Timer? _timer;

  Future<void> checkStatus() async {
    try {
      final health = await _client.health();
      if (!health.ok) {
        state = K50Status(
          state: K50ConnectionState.offline,
          label: 'K50 Disconnected',
          details: 'Bridge unreachable at ${_client.baseUrl}',
          lastChecked: DateTime.now(),
        );
        return;
      }

      if (health.deviceOnline) {
        state = K50Status(
          state: K50ConnectionState.connected,
          label: 'K50 Online',
          details: 'Biometric reader active (${health.ip ?? "Connected"})',
          lastChecked: DateTime.now(),
          ip: health.ip,
        );
      } else {
        state = K50Status(
          state: K50ConnectionState.bridgeOnly,
          label: 'K50 Reader Offline',
          details: health.error ?? 'Bridge active, reader disconnected',
          lastChecked: DateTime.now(),
          ip: health.ip,
        );
      }
    } catch (e) {
      state = K50Status(
        state: K50ConnectionState.offline,
        label: 'K50 Disconnected',
        details: e.toString(),
        lastChecked: DateTime.now(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final k50StatusProvider =
    StateNotifierProvider<K50StatusNotifier, K50Status>((ref) {
  final client = ref.watch(zkBackendClientProvider);
  return K50StatusNotifier(client);
});
