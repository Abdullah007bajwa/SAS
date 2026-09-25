import 'package:intl/intl.dart';

class SchoolCalendarService {
  SchoolCalendarService._();

  static const List<String> defaultWeeklyOffDays = ['Sunday'];

  /// Parses comma-separated weekly off days string like 'Sunday' or 'Sunday,Saturday'
  /// Returns a set of integer weekdays (Monday=1, Sunday=7)
  static Set<int> parseOffDays(String? offDaysStr) {
    if (offDaysStr == null || offDaysStr.trim().isEmpty) {
      return {DateTime.sunday};
    }
    final days = offDaysStr.split(',').map((s) => s.trim().toLowerCase()).toSet();
    final result = <int>{};
    for (final day in days) {
      switch (day) {
        case 'monday':
        case 'mon':
          result.add(DateTime.monday);
          break;
        case 'tuesday':
        case 'tue':
          result.add(DateTime.tuesday);
          break;
        case 'wednesday':
        case 'wed':
          result.add(DateTime.wednesday);
          break;
        case 'thursday':
        case 'thu':
          result.add(DateTime.thursday);
          break;
        case 'friday':
        case 'fri':
          result.add(DateTime.friday);
          break;
        case 'saturday':
        case 'sat':
          result.add(DateTime.saturday);
          break;
        case 'sunday':
        case 'sun':
          result.add(DateTime.sunday);
          break;
      }
    }
    return result.isEmpty ? {DateTime.sunday} : result;
  }

  /// Parses comma-separated or newline-separated holiday date strings (YYYY-MM-DD)
  static Set<String> parseHolidays(String? holidaysStr) {
    if (holidaysStr == null || holidaysStr.trim().isEmpty) {
      return {};
    }
    return holidaysStr
        .split(RegExp(r'[,;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  /// Checks if a given date is a weekly off-day (e.g. Sunday)
  static bool isWeekend(DateTime date, {String? weeklyOffDays}) {
    final offDays = parseOffDays(weeklyOffDays);
    return offDays.contains(date.weekday);
  }

  /// Checks if a given date is a configured school holiday
  static bool isHoliday(DateTime date, {String? holidaysStr}) {
    final holidays = parseHolidays(holidaysStr);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return holidays.contains(dateStr);
  }

  /// Checks if a date is an off-day (either weekend or school holiday)
  static bool isOffDay(DateTime date, {String? weeklyOffDays, String? holidaysStr}) {
    return isWeekend(date, weeklyOffDays: weeklyOffDays) ||
        isHoliday(date, holidaysStr: holidaysStr);
  }

  /// Returns the day name (e.g. "Sunday", "Monday")
  static String getDayName(DateTime date) {
    return DateFormat('EEEE').format(date);
  }

  /// Calculates the exact number of school working days between [start] and [end] (inclusive),
  /// skipping weekly off-days and school holidays.
  static int calculateWorkingDays({
    required DateTime start,
    required DateTime end,
    String? weeklyOffDays,
    String? holidaysStr,
  }) {
    if (end.isBefore(start)) return 0;

    var count = 0;
    var current = DateTime(start.year, start.month, start.day);
    final finish = DateTime(end.year, end.month, end.day);

    while (!current.isAfter(finish)) {
      if (!isOffDay(current, weeklyOffDays: weeklyOffDays, holidaysStr: holidaysStr)) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count;
  }

  /// Calculates total off-days (Sundays, Saturdays, holidays) in the given range.
  static int calculateOffDaysCount({
    required DateTime start,
    required DateTime end,
    String? weeklyOffDays,
    String? holidaysStr,
  }) {
    if (end.isBefore(start)) return 0;
    final totalDays = end.difference(start).inDays + 1;
    final workingDays = calculateWorkingDays(
      start: start,
      end: end,
      weeklyOffDays: weeklyOffDays,
      holidaysStr: holidaysStr,
    );
    return totalDays - workingDays;
  }
}
