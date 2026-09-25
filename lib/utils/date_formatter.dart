import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static final _dateFormat = DateFormat('MMM d, yyyy');
  static final _timeFormat = DateFormat('h:mm a');
  static final _dateTimeFormat = DateFormat('MMM d, yyyy h:mm a');
  static final _isoDate = DateFormat('yyyy-MM-dd');

  static String formatDate(DateTime? date) {
    if (date == null) return '—';
    return _dateFormat.format(date);
  }

  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '—';
    return _dateTimeFormat.format(dateTime);
  }

  static String formatEpochDate(int? epochMillis) {
    if (epochMillis == null) return '—';
    return _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(epochMillis));
  }

  static String formatEpochTime(int? epochMillis) {
    if (epochMillis == null) return '—';
    return _timeFormat.format(DateTime.fromMillisecondsSinceEpoch(epochMillis));
  }

  static String formatEpochDateTime(int? epochMillis) {
    if (epochMillis == null) return '—';
    return _dateTimeFormat.format(DateTime.fromMillisecondsSinceEpoch(epochMillis));
  }

  static String toIsoDateString(DateTime date) {
    return _isoDate.format(date);
  }
}
