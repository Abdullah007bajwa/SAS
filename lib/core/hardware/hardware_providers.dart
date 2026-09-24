import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_provider.dart';
import 'k50_bridge_launcher_service.dart';
import 'k50_device_user_map.dart';
import 'school_attendance_processor.dart';
import 'zk_attendance_dedup.dart';
import 'zk_backend_client.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in ProviderScope');
});

final zkAttendanceDedupProvider = Provider<ZkAttendanceDedup>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ZkAttendanceDedup(prefs);
});

final k50DeviceUserMapProvider = Provider<K50DeviceUserMap>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return K50DeviceUserMap(prefs);
});

final zkBackendClientProvider = Provider<ZkBackendClient>((ref) {
  return ZkBackendClient(baseUrl: 'http://127.0.0.1:8787');
});

final k50BridgeLauncherProvider = Provider<K50BridgeLauncherService>((ref) {
  return K50BridgeLauncherService();
});

final schoolAttendanceProcessorProvider = Provider<SchoolAttendanceProcessor>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final client = ref.watch(zkBackendClientProvider);
  final dedup = ref.watch(zkAttendanceDedupProvider);
  final userMap = ref.watch(k50DeviceUserMapProvider);

  return SchoolAttendanceProcessor(
    db: db,
    backendClient: client,
    dedup: dedup,
    deviceUserMap: userMap,
  );
});
