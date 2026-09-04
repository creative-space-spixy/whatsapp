class ConversationMessage {
  final String id;
  final String? userId;
  final String? message;
  final String? response;
  final DateTime createdAt;
  final String? threadId;
  final String? messageId;
  final String sender;

  ConversationMessage({
    required this.id,
    this.userId,
    this.message,
    this.response,
    required this.createdAt,
    this.threadId,
    this.messageId,
    required this.sender,
  });

  factory ConversationMessage.fromMap(Map<String, dynamic> map) {
    return ConversationMessage(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      message: map['message'] as String?,
      response: map['response'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      threadId: map['thread_id'] as String?,
      messageId: map['message_id'] as String?,
      sender: map['sender'] as String? ?? '',
    );
  }

  bool get isAnswered => response != null && response!.trim().isNotEmpty;
}
