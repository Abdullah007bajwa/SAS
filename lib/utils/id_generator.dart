class IdGenerator {
  IdGenerator._();

  /// Generates formatted student code from numeric sequence: e.g. 1001 -> STU-1001
  static String formatStudentCode(int id) {
    return 'STU-$id';
  }

  /// Extracts section letter or identifier from section name:
  /// e.g. "Section 3-A" -> "A", "Section B" -> "B", "A" -> "A"
  static String extractSectionLetter(String sectionName) {
    final match = RegExp(r'[A-Za-z]+$').firstMatch(sectionName.trim());
    return (match?.group(0) ?? 'A').toUpperCase();
  }

  /// Converts a section letter to 1-based index: A->1, B->2, C->3 ...
  static int sectionLetterToIndex(String sectionLetter) {
    if (sectionLetter.isEmpty) return 1;
    final code = sectionLetter.toUpperCase().codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      return code - 64; // A -> 1, B -> 2, etc.
    }
    return 1;
  }

  /// Formats class and section-aware student code:
  /// e.g. classLevel=3, sectionName="Section 3-A", sequence=17 -> "C3A-017"
  /// e.g. classLevel=10, sectionName="Section 10-A", sequence=18 -> "C10A-018"
  static String formatClassAwareStudentCode({
    required int classLevel,
    required String sectionName,
    required int sequence,
    String prefix = 'C',
  }) {
    final secLetter = extractSectionLetter(sectionName);
    final padRoll = sequence.toString().padLeft(3, '0');
    return '$prefix$classLevel$secLetter-$padRoll';
  }

  /// Generates a purely numeric biometric ID for K50:
  /// Formula: [classLevel * 1000] + [sectionIndex * 100] + [sequence]
  /// e.g. Class 3, Section A (1), seq 17 -> 3117
  /// e.g. Class 10, Section A (1), seq 18 -> 10118
  static int generateClassAwareBiometricId({
    required int classLevel,
    required String sectionName,
    required int sequence,
  }) {
    final secIdx = sectionLetterToIndex(extractSectionLetter(sectionName));
    return (classLevel * 1000) + (secIdx * 100) + sequence;
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
