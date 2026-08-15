import 'package:intl/intl.dart';

/// Compact timestamps for chat and trip lists.
abstract final class RelativeTime {
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _weekday = DateFormat('EEE');
  static final DateFormat _date = DateFormat('d MMM');

  /// "2:14 pm" today, "Tue" this week, "12 Aug" beyond that.
  static String short(DateTime when, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final local = when.toLocal();
    final sameDay =
        local.year == reference.year &&
        local.month == reference.month &&
        local.day == reference.day;
    if (sameDay) return _time.format(local).toLowerCase();

    final difference = reference.difference(local);
    if (difference.inDays < 7 && !difference.isNegative) {
      return _weekday.format(local);
    }
    return _date.format(local);
  }

  /// "2:14 pm" -- used inside a conversation where the day is already known.
  static String timeOfDay(DateTime when) =>
      _time.format(when.toLocal()).toLowerCase();
}
