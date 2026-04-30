import 'package:intl/intl.dart';

class DateHelper {
  const DateHelper._();

  static String formatMessageTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();

    if (_isSameDay(local, now)) {
      return DateFormat('hh:mm a').format(local);
    }

    if (now.difference(local).inDays < 7) {
      return DateFormat('EEE').format(local);
    }

    return DateFormat('dd MMM').format(local);
  }

  static String formatBubbleTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime.toLocal());
  }

  static String formatDateSeparator(DateTime dateTime) {
    final local = dateTime.toLocal();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    if (_isSameDay(local, today)) {
      return 'Today';
    }

    if (_isSameDay(local, yesterday)) {
      return 'Yesterday';
    }

    return DateFormat('dd/MM/yyyy').format(local);
  }

  static bool isSameCalendarDay(DateTime left, DateTime right) {
    return _isSameDay(left.toLocal(), right.toLocal());
  }

  static String formatFull(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dateTime.toLocal());
  }

  static String formatLastSeen(DateTime lastSeen) {
    final local = lastSeen.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    }
    if (_isSameDay(local, now)) {
      return 'at ${DateFormat('hh:mm a').format(local)}';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(local, yesterday)) {
      return 'Yesterday at ${DateFormat('hh:mm a').format(local)}';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    }

    return DateFormat('dd MMM yyyy').format(local);
  }

  static bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
