class ChatThreadResolver {
  static const String announcementThreadId = 'announcements';
  static const String adminTeacherThreadId = 'admin_teacher';
  static const String _keyPersonStudentThreadPrefix = 'keyperson_student_';

  const ChatThreadResolver._();

  static String studentTeacherThreadId(String studentLmsUserId) {
    return studentLmsUserId.trim();
  }

  static String studentContactPersonThreadId(String studentLmsUserId) {
    return '$_keyPersonStudentThreadPrefix${studentLmsUserId.trim()}';
  }

  static bool isStudentContactPersonThreadId(String threadId) {
    return threadId.startsWith(_keyPersonStudentThreadPrefix);
  }

  static String? studentIdFromContactPersonThreadId(String threadId) {
    if (!isStudentContactPersonThreadId(threadId)) return null;

    final studentId = threadId.substring(_keyPersonStudentThreadPrefix.length);
    return studentId.trim().isEmpty ? null : studentId;
  }
}
