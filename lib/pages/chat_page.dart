import 'package:flutter/material.dart';

import '../models/conversation_message.dart';
import '../services/conversations_service.dart';
import '../widgets/message_bubble.dart';

class ChatPage extends StatefulWidget {
  final String sender;

  const ChatPage({super.key, required this.sender});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _service = ConversationsService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final Stream<List<ConversationMessage>> _stream;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _stream = _service.streamAll();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send(List<ConversationMessage> currentMessages) async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    // Reply into the most recent unanswered row so its `response` gets
    // filled in; if every row already has a response, the Edge Function
    // inserts a fresh row instead.
    final pending = currentMessages.where((m) => !m.isAnswered).toList();
    final replyTo = pending.isEmpty ? null : pending.last;
    final threadId = currentMessages.isEmpty ? null : currentMessages.last.threadId;

    try {
      await _service.sendReply(
        sender: widget.sender,
        message: text,
        replyToRowId: replyTo?.id,
        threadId: threadId,
      );
      _textController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.sender)),
      body: StreamBuilder<List<ConversationMessage>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final messages = snapshot.data!
              .where((m) => m.sender == widget.sender)
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

          _scrollToBottom();

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final bubbles = <Widget>[];
                    if (m.message != null && m.message!.trim().isNotEmpty) {
                      bubbles.add(MessageBubble(
                        text: m.message!,
                        time: m.createdAt,
                        fromCustomer: true,
                      ));
                    }
                    if (m.isAnswered) {
                      bubbles.add(MessageBubble(
                        text: m.response!,
                        time: m.createdAt,
                        fromCustomer: false,
                      ));
                    }
                    return Column(children: bubbles);
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(messages),
                          decoration: InputDecoration(
                            hintText: 'Type a reply…',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton.filled(
                              icon: const Icon(Icons.send),
                              onPressed: () => _send(messages),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
