class Message {
  final String id;
  final String senderName;
  final String senderRole;
  final String text;
  final bool isMe;
  final String time;

  Message({
    required this.id,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.isMe,
    required this.time,
  });
}