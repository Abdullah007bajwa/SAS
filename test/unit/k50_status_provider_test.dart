import 'package:flutter_test/flutter_test.dart';
import 'package:school_attendance_portal/core/hardware/k50_status_provider.dart';
import 'package:school_attendance_portal/core/hardware/zk_backend_client.dart';

class FakeZkBackendClient extends ZkBackendClient {
  FakeZkBackendClient() : super(baseUrl: 'http://127.0.0.1:8787');

  BackendHealthResponse nextHealth = const BackendHealthResponse(ok: false);

  @override
  Future<BackendHealthResponse> health() async {
    return nextHealth;
  }
}

void main() {
  group('K50StatusNotifier & State Tests', () {
    test('Initial or unreachable bridge reports offline state', () async {
      final client = FakeZkBackendClient();
      client.nextHealth = const BackendHealthResponse(
        ok: false,
        error: 'Connection refused',
      );

      final notifier = K50StatusNotifier(client);
      await notifier.checkStatus();

      expect(notifier.state.state, equals(K50ConnectionState.offline));
      expect(notifier.state.label, equals('K50 Disconnected'));
      expect(notifier.state.isBridgeUp, isFalse);
      expect(notifier.state.isFullyOnline, isFalse);

      notifier.dispose();
    });

    test('Bridge running but biometric reader offline reports bridgeOnly', () async {
      final client = FakeZkBackendClient();
      client.nextHealth = const BackendHealthResponse(
        ok: true,
        deviceOnline: false,
        ip: '192.168.1.201',
        error: 'Cannot connect to device socket',
      );

      final notifier = K50StatusNotifier(client);
      await notifier.checkStatus();

      expect(notifier.state.state, equals(K50ConnectionState.bridgeOnly));
      expect(notifier.state.label, equals('K50 Reader Offline'));
      expect(notifier.state.isBridgeUp, isTrue);
      expect(notifier.state.isFullyOnline, isFalse);
      expect(notifier.state.details, contains('Cannot connect to device socket'));

      notifier.dispose();
    });

    test('Bridge running and biometric reader connected reports connected', () async {
      final client = FakeZkBackendClient();
      client.nextHealth = const BackendHealthResponse(
        ok: true,
        deviceOnline: true,
        ip: '192.168.1.201',
      );

      final notifier = K50StatusNotifier(client);
      await notifier.checkStatus();

      expect(notifier.state.state, equals(K50ConnectionState.connected));
      expect(notifier.state.label, equals('K50 Online'));
      expect(notifier.state.isBridgeUp, isTrue);
      expect(notifier.state.isFullyOnline, isTrue);
      expect(notifier.state.ip, equals('192.168.1.201'));

      notifier.dispose();
    });
  });
}
