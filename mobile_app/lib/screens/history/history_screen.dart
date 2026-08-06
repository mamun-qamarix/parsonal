import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/vault_service.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/vault_entry_card.dart';
import '../vault/entry_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<VaultEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final entries = await VaultService().listEntries(vmk);
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mounted)
      setState(() {
        _entries = entries;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('হিস্টরি')),
      body: _loading
          ? const ShimmerFeedList()
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? const Center(child: Text('এখনো কোনো কার্যক্রম নেই'))
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                      itemBuilder: (context, i) => VaultEntryCard(
                        entry: _entries[i],
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  EntryDetailScreen(entryId: _entries[i].id),
                            ),
                          );
                          _load();
                        },
                      ),
                    ),
            ),
    );
  }
}
