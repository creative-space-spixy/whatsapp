import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation_message.dart';
import '../services/conversations_service.dart';
import '../services/labels_service.dart';
import 'chat_page.dart';

const List<String> _kTabs = ['Unread', 'All', ...kConversationLabels];

class ConversationsListPage extends StatefulWidget {
  const ConversationsListPage({super.key});

  @override
  State<ConversationsListPage> createState() => _ConversationsListPageState();
}

class _ConversationsListPageState extends State<ConversationsListPage> {
  final _service = ConversationsService();
  final _labelsService = LabelsService();
  late final Stream<List<ConversationMessage>> _messagesStream;
  late final Stream<Map<String, String>> _labelsStream;
  final _searchController = TextEditingController();
  String _search = '';
  String _selectedTab = 'Unread';

  @override
  void initState() {
    super.initState();
    _messagesStream = _service.streamAll();
    _labelsStream = _labelsService.streamLabels();
    _searchController.addListener(() {
      setState(() => _search = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _labelColor(String label) {
    switch (label) {
      case 'Spam':
        return Colors.red;
      case 'Lead':
        return Colors.blue;
      case 'Potential':
        return Colors.orange;
      case 'Collab':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showLabelSheet(String sender, String? currentLabel) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(sender, style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: const Text('Flag this conversation as'),
            ),
            for (final label in kConversationLabels)
              ListTile(
                leading: CircleAvatar(radius: 6, backgroundColor: _labelColor(label)),
                title: Text(label),
                trailing: currentLabel == label ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, label),
              ),
            if (currentLabel != null)
              ListTile(
                leading: const Icon(Icons.label_off_outlined),
                title: const Text('Clear label'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _labelsService.setLabel(sender, result.isEmpty ? null : result);
  }

  List<ConversationSummary> _applyTabFilter(
    List<ConversationSummary> all,
    Map<String, String> labels,
  ) {
    switch (_selectedTab) {
      case 'Unread':
        // A conversation with no sender number can't be replied to from
        // here, so it stays out of the actionable Unread queue and just
        // sits under All instead.
        return all.where((s) => s.pendingCount > 0 && s.sender.trim().isNotEmpty).toList();
      case 'All':
        return all;
      default:
        return all.where((s) => labels[s.sender] == _selectedTab).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Conversations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by number',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kTabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tab = _kTabs[index];
                  final selected = tab == _selectedTab;
                  return ChoiceChip(
                    label: Text(tab),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedTab = tab),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ConversationMessage>>(
              stream: _messagesStream,
              builder: (context, messagesSnapshot) {
                if (messagesSnapshot.hasError) {
                  return Center(child: Text('Error: ${messagesSnapshot.error}'));
                }
                if (!messagesSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<Map<String, String>>(
                  stream: _labelsStream,
                  builder: (context, labelsSnapshot) {
                    final labels = labelsSnapshot.data ?? const {};
                    var summaries = _service.groupBySender(messagesSnapshot.data!);
                    summaries = _applyTabFilter(summaries, labels);
                    if (_search.isNotEmpty) {
                      summaries = summaries.where((s) => s.sender.contains(_search)).toList();
                    }

                    if (summaries.isEmpty) {
                      return const Center(child: Text('No conversations here'));
                    }

                    return ListView.separated(
                      itemCount: summaries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = summaries[index];
                        final label = labels[s.sender];
                        return GestureDetector(
                          onLongPress: () => _showLabelSheet(s.sender, label),
                          onSecondaryTap: () => _showLabelSheet(s.sender, label),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: label != null ? _labelColor(label) : null,
                              child: Text(
                                s.sender.isNotEmpty ? s.sender.substring(s.sender.length - 2) : '?',
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(s.sender),
                                if (label != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _labelColor(label).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(fontSize: 11, color: _labelColor(label)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              s.previewText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  DateFormat('MMM d, h:mm a').format(s.latest.createdAt.toLocal()),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (s.pendingCount > 0) ...[
                                  const SizedBox(height: 4),
                                  CircleAvatar(
                                    radius: 9,
                                    backgroundColor: Colors.green,
                                    child: Text(
                                      '${s.pendingCount}',
                                      style: const TextStyle(fontSize: 11, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatPage(sender: s.sender),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
