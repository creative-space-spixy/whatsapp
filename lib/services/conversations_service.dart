import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation_message.dart';

class ConversationSummary {
  final String sender;
  final List<ConversationMessage> messages;

  ConversationSummary({required this.sender, required this.messages});

  ConversationMessage get latest => messages.last;

  /// A row with no response yet means the bot/agent hasn't replied --
  /// surfaced in the list as a "needs reply" indicator.
  int get pendingCount => messages.where((m) => !m.isAnswered).length;

  String get previewText {
    final last = latest;
    if (last.isAnswered) return last.response!.trim();
    return last.message?.trim() ?? '';
  }
}

/// All state here is `static` so every ConversationsService() instance
/// shares one fetch + one Realtime channel for the whole app, rather than
/// each page opening its own.
class ConversationsService {
  final _client = Supabase.instance.client;

  static const int _rowCap = 2000;

  static final Map<String, ConversationMessage> _byId = {};
  static StreamController<List<ConversationMessage>>? _controller;
  static Future<void>? _startFuture;

  void _emit() {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    final rows = _byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    controller.add(rows);
  }

  void _applyRow(Map<String, dynamic> row) {
    final m = ConversationMessage.fromMap(row);
    _byId[m.id] = m;
    _emit();
  }

  Future<void> _start() async {
    final rows = await _client
        .from('host_conversations')
        .select()
        .order('created_at', ascending: false)
        .limit(_rowCap);
    for (final row in (rows as List)) {
      _byId[row['id'] as String] = ConversationMessage.fromMap(row as Map<String, dynamic>);
    }
    _emit();

    // Lives for the app's lifetime, deliberately never unsubscribed --
    // this is a single app-wide singleton (see the class doc comment).
    _client.channel('host_conversations-live')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'host_conversations',
        callback: (payload) => _applyRow(payload.newRecord),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'host_conversations',
        callback: (payload) => _applyRow(payload.newRecord),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'host_conversations',
        callback: (payload) {
          final deletedId = payload.oldRecord['id'] as String?;
          if (deletedId != null) _byId.remove(deletedId);
          _emit();
        },
      )
      ..subscribe();
  }

  /// Live view of all conversation rows, sorted by parsed DateTime -- never
  /// trust the raw created_at strings for ordering, see below. Grouping by
  /// sender (rather than thread_id) happens client-side since a single
  /// WhatsApp number can span multiple thread_ids over time.
  ///
  /// This deliberately avoids supabase_flutter's built-in `.stream()`: its
  /// internal resort compares created_at as a raw *string*, and Realtime
  /// pushes new inserts as "...T02:14:53+00:00" while the initial REST fetch
  /// returns Postgres's own "...  02:14:53+00" (space-separated) -- mixing
  /// the two formats in one string-sort scrambles the order the moment a
  /// live insert lands, and `.limit()` on top of that can silently drop the
  /// newest rows once the table passes the cap. Fetching once and merging
  /// realtime events into a Dart map keyed by id sidesteps both problems.
  Stream<List<ConversationMessage>> streamAll() {
    _controller ??= StreamController<List<ConversationMessage>>.broadcast(
      onListen: () {
        _startFuture ??= _start();
      },
    );
    if (_byId.isNotEmpty) {
      // A listener attaching after the first fetch (e.g. opening a chat
      // page) should see current data immediately rather than waiting for
      // the next change.
      scheduleMicrotask(_emit);
    }
    return _controller!.stream;
  }

  List<ConversationSummary> groupBySender(List<ConversationMessage> rows) {
    final bySender = <String, List<ConversationMessage>>{};
    for (final row in rows) {
      bySender.putIfAbsent(row.sender, () => []).add(row);
    }
    final summaries = bySender.entries.map((e) {
      final messages = e.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return ConversationSummary(sender: e.key, messages: messages);
    }).toList();
    summaries.sort(
      (a, b) => b.latest.createdAt.compareTo(a.latest.createdAt),
    );
    return summaries;
  }

  /// Sends a WhatsApp reply via the send-whatsapp-reply Edge Function (which
  /// holds the Meta access token server-side) and records it in
  /// host_conversations. If [replyToRowId] is a row that's still unanswered,
  /// the function fills in its `response`; otherwise it inserts a fresh row.
  ///
  /// The function writes with the service-role key, so its response's `row`
  /// is applied locally right away instead of waiting on a Realtime event --
  /// that's what makes a sent message show up in the chat immediately.
  Future<void> sendReply({
    required String sender,
    required String message,
    String? replyToRowId,
    String? threadId,
  }) async {
    final res = await _client.functions.invoke(
      'send-whatsapp-reply',
      body: {
        'sender': sender,
        'message': message,
        if (replyToRowId != null) 'rowId': replyToRowId,
        if (threadId != null) 'threadId': threadId,
      },
    );

    final data = res.data;
    if (res.status != 200 || (data is Map && data['error'] != null)) {
      throw Exception(
        data is Map ? (data['error']?.toString() ?? 'Failed to send message') : 'Failed to send message',
      );
    }

    if (data is Map && data['row'] is Map) {
      _applyRow(Map<String, dynamic>.from(data['row'] as Map));
    }
  }
}
