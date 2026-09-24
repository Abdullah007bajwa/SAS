import 'dart:io';

class PlatformHelper {
  PlatformHelper._();

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static bool get isWindows => Platform.isWindows;
  static bool get isLinux => Platform.isLinux;
}
