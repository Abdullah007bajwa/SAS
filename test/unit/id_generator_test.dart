import 'package:flutter_test/flutter_test.dart';
import 'package:school_attendance_portal/utils/id_generator.dart';

void main() {
  group('IdGenerator Tests', () {
    test('formatStudentCode formats correctly', () {
      expect(IdGenerator.formatStudentCode(1001), 'STU-1001');
      expect(IdGenerator.formatStudentCode(7999), 'STU-7999');
    });

    test('formatStaffCode formats with default and custom prefix', () {
      expect(IdGenerator.formatStaffCode(8001), 'TCH-8001');
      expect(IdGenerator.formatStaffCode(8002, prefix: 'ADM'), 'ADM-8002');
      expect(IdGenerator.formatStaffCode(8003, prefix: 'STF'), 'STF-8003');
    });

    test('extractNumeric retrieves numeric digits from codes', () {
      expect(IdGenerator.extractNumeric('STU-1001'), '1001');
      expect(IdGenerator.extractNumeric('TCH-8050'), '8050');
      expect(IdGenerator.extractNumeric('ADM001'), '001');
      expect(IdGenerator.extractNumeric('NONDIGIT'), isNull);
    });

    test('formatClassAwareStudentCode formats class and section aware codes', () {
      expect(
        IdGenerator.formatClassAwareStudentCode(classLevel: 3, sectionName: 'Section 3-A', sequence: 17),
        'C3A-017',
      );
      expect(
        IdGenerator.formatClassAwareStudentCode(classLevel: 10, sectionName: 'Section 10-A', sequence: 18),
        'C10A-018',
      );
      expect(
        IdGenerator.formatClassAwareStudentCode(classLevel: 5, sectionName: 'Section B', sequence: 4),
        'C5B-004',
      );
    });

    test('generateClassAwareBiometricId produces numeric hardware ID', () {
      expect(
        IdGenerator.generateClassAwareBiometricId(classLevel: 3, sectionName: 'Section 3-A', sequence: 17),
        3117,
      );
      expect(
        IdGenerator.generateClassAwareBiometricId(classLevel: 10, sectionName: 'Section 10-A', sequence: 18),
        10118,
      );
      expect(
        IdGenerator.generateClassAwareBiometricId(classLevel: 1, sectionName: 'B', sequence: 5),
        1205,
      );
    });
  });
}
