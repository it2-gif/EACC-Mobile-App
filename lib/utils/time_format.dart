import 'package:cloud_firestore/cloud_firestore.dart';

String formatMessageTime(dynamic createdAt) {
  if (createdAt == null) return '';

  DateTime? dateTime;
  if (createdAt is Timestamp) {
    dateTime = createdAt.toDate();
  } else if (createdAt is DateTime) {
    dateTime = createdAt;
  }

  if (dateTime == null) return '';

  return formatClockTime(dateTime);
}

String formatThreadTime(dynamic timestamp) {
  if (timestamp == null) return '';

  DateTime? dateTime;
  if (timestamp is Timestamp) {
    dateTime = timestamp.toDate();
  } else if (timestamp is DateTime) {
    dateTime = timestamp;
  }

  if (dateTime == null) return '';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(dateTime.year, dateTime.month, dateTime.day);

  final time = formatClockTime(dateTime);

  if (messageDay == today) return time;

  final yesterday = today.subtract(const Duration(days: 1));
  if (messageDay == yesterday) return 'Yesterday';

  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}

String formatClockTime(DateTime dateTime) {
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');

  return '$hour:$minute $period';
}
