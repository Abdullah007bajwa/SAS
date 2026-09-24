class IdGenerator {
  IdGenerator._();

  /// Generates formatted student code from numeric sequence: e.g. 1001 -> STU-1001
  static String formatStudentCode(int id) {
    return 'STU-$id';
  }

  /// Generates formatted employee code from numeric sequence: e.g. 8001 -> TCH-8001
  static String formatStaffCode(int id, {String prefix = 'TCH'}) {
    return '$prefix-$id';
  }

  /// Extracts numeric digits from strings like 'STU-1001' -> '1001'
  static String? extractNumeric(String code) {
    final match = RegExp(r'\d+').firstMatch(code);
    return match?.group(0);
  }
}
