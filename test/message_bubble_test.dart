import 'package:chatt_eacc/widgets/message_bubble.dart';
import 'package:flutter_test/flutter_test.dart';

MessageBubble buildBubble({
  required String senderName,
  required String senderRole,
  required String currentUserRole,
  required String currentSenderName,
}) {
  return MessageBubble(
    type: 'text',
    text: 'Test message',
    mediaUrl: null,
    senderName: senderName,
    senderRole: senderRole,
    currentUserRole: currentUserRole,
    currentSenderName: currentSenderName,
    createdAt: DateTime(2026, 6, 18, 13, 30),
    editedAt: null,
    deletedAt: null,
  );
}

void main() {
  group('message ownership', () {
    test('student sees their own message as sent by them', () {
      final bubble = buildBubble(
        senderName: 'Esam Test',
        senderRole: 'student',
        currentUserRole: 'student',
        currentSenderName: 'Esam Test',
      );

      expect(bubble.isMe, isTrue);
    });

    test('teacher sees their own message as sent by them', () {
      final bubble = buildBubble(
        senderName: 'Mohamed El-Sayad',
        senderRole: 'teacher',
        currentUserRole: 'teacher',
        currentSenderName: 'Mohamed El-Sayad',
      );

      expect(bubble.isMe, isTrue);
    });

    test('admin sees every message as an incoming message', () {
      final bubble = buildBubble(
        senderName: 'EACC Admin',
        senderRole: 'admin',
        currentUserRole: 'admin',
        currentSenderName: 'EACC Admin',
      );

      expect(bubble.isMe, isFalse);
    });
  });

  test('admin messages use the official sender label', () {
    final bubble = buildBubble(
      senderName: 'Another Name',
      senderRole: 'admin',
      currentUserRole: 'student',
      currentSenderName: 'Esam Test',
    );

    expect(bubble.displaySender, 'EACC Admin');
  });
}
