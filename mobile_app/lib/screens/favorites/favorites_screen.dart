import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/vault_service.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/vault_entry_card.dart';
import '../vault/entry_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<VaultEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final entries = await VaultService().listEntries(vmk, favoritesOnly: true);
    if (mounted)
      setState(() {
        _entries = entries;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ফেভারিট')),
      body: _loading
          ? const ShimmerFeedList()
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? const Center(child: Text('এখনো কিছু ফেভারিটে যোগ করা হয়নি'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: VaultEntryCard(
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
            ),
    );
  }
}
