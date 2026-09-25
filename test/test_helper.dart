import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';

void setupSqliteForTests() {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('/usr/lib64/libsqlite3.so.0');
      } catch (_) {
        try {
          return DynamicLibrary.open('libsqlite3.so');
        } catch (_) {
          return DynamicLibrary.open('/home/zozo/.local/lib/libsqlite3.so');
        }
      }
    });
  }
}
