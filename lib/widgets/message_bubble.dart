import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final DateTime time;
  final bool fromCustomer;

  const MessageBubble({
    super.key,
    required this.text,
    required this.time,
    required this.fromCustomer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = fromCustomer ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    final fg = fromCustomer ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;

    return Align(
      alignment: fromCustomer ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(fromCustomer ? 2 : 14),
            bottomRight: Radius.circular(fromCustomer ? 14 : 2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: TextStyle(color: fg)),
            const SizedBox(height: 4),
            Text(
              DateFormat('h:mm a').format(time.toLocal()),
              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
