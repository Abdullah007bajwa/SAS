import 'package:flutter_test/flutter_test.dart';
import 'package:school_attendance_portal/utils/date_formatter.dart';

void main() {
  group('DateFormatter Tests', () {
    test('formatDate formats DateTime correctly', () {
      final dt = DateTime(2026, 9, 25);
      expect(DateFormatter.formatDate(dt), 'Sep 25, 2026');
      expect(DateFormatter.formatDate(null), '—');
    });

    test('toIsoDateString formats to YYYY-MM-DD', () {
      final dt = DateTime(2026, 9, 25, 14, 30);
      expect(DateFormatter.toIsoDateString(dt), '2026-09-25');
    });

    test('formatEpochTime formats time correctly', () {
      final dt = DateTime(2026, 9, 25, 8, 30);
      final epoch = dt.millisecondsSinceEpoch;
      expect(DateFormatter.formatEpochTime(epoch), '8:30 AM');
      expect(DateFormatter.formatEpochTime(null), '—');
    });

    test('formatDateTime formats full date and time', () {
      final dt = DateTime(2026, 9, 25, 8, 30);
      expect(DateFormatter.formatDateTime(dt), 'Sep 25, 2026 8:30 AM');
      expect(DateFormatter.formatDateTime(null), '—');
    });
  });
}
