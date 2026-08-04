import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/vault_service.dart';
import '../../widgets/countdown_card.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/vault_entry_card.dart';
import '../favorites/favorites_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';
import '../vault/consent_requests_screen.dart';
import '../vault/create_entry_screen.dart';
import '../vault/entry_detail_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  late final TabController _roleTab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _roleTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myRole = context.watch<SessionProvider>().role ?? 'husband';
    return DefaultTabController(
      length: 2,
      initialIndex: myRole == 'husband' ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Our Vault'),
          actions: [
            IconButton(icon: const Icon(Icons.history), tooltip: 'History', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen()))),
            IconButton(icon: const Icon(Icons.favorite_border), tooltip: 'Favorites', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
            IconButton(icon: const Icon(Icons.mark_email_unread_outlined), tooltip: 'Approvals', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConsentRequestsScreen()))),
            IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Husband'), Tab(text: 'Wife')]),
        ),
        body: Column(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: CountdownCard()),
            Expanded(
              child: TabBarView(
                children: [
                  _RoleVaultView(role: 'husband'),
                  _RoleVaultView(role: 'wife'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleVaultView extends StatefulWidget {
  final String role;
  const _RoleVaultView({required this.role});

  @override
  State<_RoleVaultView> createState() => _RoleVaultViewState();
}

class _RoleVaultViewState extends State<_RoleVaultView> with SingleTickerProviderStateMixin {
  late final TabController _typeTab = TabController(length: 3, vsync: this);
  final _service = VaultService();
  final _contentTypes = ['text', 'photo', 'video'];
  Map<String, List<VaultEntry>> _entries = {};
  List<Category> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final results = await Future.wait(_contentTypes.map((t) => _service.listEntries(vmk, authorRole: widget.role, contentType: t)));
    final categories = await _service.listCategories(vmk, 'vault');
    if (!mounted) return;
    setState(() {
      _entries = {for (var i = 0; i < _contentTypes.length; i++) _contentTypes[i]: results[i]};
      _categories = categories;
      _loading = false;
    });
  }

  Future<void> _createNew() async {
    final type = _contentTypes[_typeTab.index];
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CreateEntryScreen(contentType: type, categories: _categories)));
    if (created == true) _load();
  }

  @override
  void dispose() {
    _typeTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: _createNew, child: const Icon(Icons.add)),
      body: Column(
      children: [
        TabBar(controller: _typeTab, tabs: const [Tab(text: 'Text'), Tab(text: 'Photo'), Tab(text: 'Video')], labelColor: Theme.of(context).colorScheme.primary),
        Expanded(
          child: _loading
              ? const ShimmerFeedList()
              : TabBarView(
                  controller: _typeTab,
                  children: _contentTypes.map((type) {
                    final list = _entries[type] ?? [];
                    if (list.isEmpty) {
                      return const Center(child: Text('Nothing here yet'));
                    }
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: list.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: VaultEntryCard(
                            entry: list[i],
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryDetailScreen(entryId: list[i].id)));
                              _load();
                            },
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
      ),
    );
  }
}
