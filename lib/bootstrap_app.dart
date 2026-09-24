import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/database/app_database.dart';
import 'core/database/database_connection.dart';
import 'core/database/database_provider.dart';
import 'core/hardware/hardware_providers.dart';
import 'school_attendance_app.dart';

/// Bootstraps local database, environment variables, SharedPreferences, and cloud connection.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  Widget? _readyApp;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      try {
        await dotenv.load(fileName: '.env');
      } catch (_) {
        // Fallback if .env is missing or cannot be read
      }

      final prefs = await SharedPreferences.getInstance();
      final database = AppDatabase(openAppDatabaseConnection());

      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
      final cloudReady = supabaseUrl != null &&
          supabaseAnonKey != null &&
          supabaseUrl.isNotEmpty &&
          !supabaseUrl.contains('your-supabase-project');

      if (cloudReady) {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        );
      }

      if (!mounted) return;

      setState(() {
        _readyApp = ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(database),
          ],
          child: const SchoolAttendanceApp(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_readyApp != null) return _readyApp!;

    if (_initError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Initialization failed: $_initError',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      );
    }

    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF1E3A8A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
