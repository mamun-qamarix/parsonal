import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
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
  late final TabController _typeTab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _typeTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Our Vault'),
        actions: [
          IconButton(icon: const Icon(Icons.history), tooltip: 'History', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen()))),
          IconButton(icon: const Icon(Icons.favorite_border), tooltip: 'Favorites', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
          IconButton(icon: const Icon(Icons.mark_email_unread_outlined), tooltip: 'Approvals', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConsentRequestsScreen()))),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
        bottom: TabBar(
          controller: _typeTab,
          tabs: const [Tab(text: 'টেক্সট'), Tab(text: 'ছবি'), Tab(text: 'ভিডিও')],
        ),
      ),
      body: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: CountdownCard()),
          Expanded(
            child: TabBarView(
              controller: _typeTab,
              children: const [
                _ContentTypeView(contentType: 'text'),
                _ContentTypeView(contentType: 'photo'),
                _ContentTypeView(contentType: 'video'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One content type (text/photo/video); the husband/wife filter lives
/// INSIDE this, not as the outer navigation, per the redesign -- both
/// roles' entries for this content type are loaded up front so switching
/// the filter is instant, no reload. Defaults to the OTHER spouse's
/// content, since that's usually what you open the app to check.
class _ContentTypeView extends StatefulWidget {
  final String contentType;
  const _ContentTypeView({required this.contentType});

  @override
  State<_ContentTypeView> createState() => _ContentTypeViewState();
}

class _ContentTypeViewState extends State<_ContentTypeView> {
  final _service = VaultService();
  Map<String, List<VaultEntry>> _entriesByRole = {};
  List<Category> _categories = [];
  bool _loading = true;
  late String _filterRole;

  @override
  void initState() {
    super.initState();
    final myRole = context.read<SessionProvider>().role ?? 'husband';
    _filterRole = myRole == 'husband' ? 'wife' : 'husband';
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final results = await Future.wait([
      _service.listEntries(vmk, authorRole: 'husband', contentType: widget.contentType),
      _service.listEntries(vmk, authorRole: 'wife', contentType: widget.contentType),
    ]);
    final categories = await _service.listCategories(vmk, 'vault');
    if (!mounted) return;
    setState(() {
      _entriesByRole = {'husband': results[0], 'wife': results[1]};
      _categories = categories;
      _loading = false;
    });
  }

  Future<void> _createNew() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CreateEntryScreen(contentType: widget.contentType, categories: _categories)));
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _entriesByRole[_filterRole] ?? [];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: _createNew, child: const Icon(Icons.add)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: _RoleFilterChip(
                    label: 'স্বামী',
                    icon: Icons.man,
                    color: AppColors.husband,
                    selected: _filterRole == 'husband',
                    onTap: () => setState(() => _filterRole = 'husband'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RoleFilterChip(
                    label: 'স্ত্রী',
                    icon: Icons.woman,
                    color: AppColors.wife,
                    selected: _filterRole == 'wife',
                    onTap: () => setState(() => _filterRole = 'wife'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const ShimmerFeedList()
                : list.isEmpty
                    ? const Center(child: Text('এখনো কিছু নেই'))
                    : RefreshIndicator(
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
                      ),
          ),
        ],
      ),
    );
  }
}

class _RoleFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _RoleFilterChip({required this.label, required this.icon, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color : Colors.grey.withValues(alpha: 0.35), width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? color : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? color : Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
