import 'package:supabase_flutter/supabase_flutter.dart';

const List<String> kConversationLabels = ['Spam', 'Lead', 'Potential', 'Collab'];

class LabelsService {
  final _client = Supabase.instance.client;

  /// sender -> label, for every number that's been manually flagged.
  Stream<Map<String, String>> streamLabels() {
    return _client.from('conversation_labels').stream(primaryKey: ['sender']).map(
          (rows) => {for (final r in rows) r['sender'] as String: r['label'] as String},
        );
  }

  Future<void> setLabel(String sender, String? label) async {
    if (label == null) {
      await _client.from('conversation_labels').delete().eq('sender', sender);
    } else {
      await _client.from('conversation_labels').upsert({
        'sender': sender,
        'label': label,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }
}
