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
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// One mixed feed -- text/photo/video interleaved by recency, like a
/// social-media home feed -- with a multi-select filter bar (content
/// type + author) instead of separate tabs. See DECISIONS.md.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _service = VaultService();
  List<VaultEntry> _entries = [];
  List<Category> _categories = [];
  bool _loading = true;
  final Set<String> _typeFilter = {'text', 'photo', 'video'};
  final Set<String> _roleFilter = {'husband', 'wife'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final results = await Future.wait([
      _service.listEntries(vmk),
      _service.listCategories(vmk, 'vault'),
    ]);
    if (!mounted) return;
    setState(() {
      _entries = results[0] as List<VaultEntry>;
      _categories = results[1] as List<Category>;
      _loading = false;
    });
  }

  void _toggleFilter(Set<String> group, String value) {
    setState(() {
      if (group.contains(value)) {
        if (group.length > 1)
          group.remove(value); // always leave at least one on
      } else {
        group.add(value);
      }
    });
  }

  Future<void> _createNew() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'কী যোগ করতে চান?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Iconsax.document_text),
              title: const Text('টেক্সট'),
              onTap: () => Navigator.pop(context, 'text'),
            ),
            ListTile(
              leading: const Icon(Iconsax.image),
              title: const Text('ছবি'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Iconsax.video),
              title: const Text('ভিডিও'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CreateEntryScreen(contentType: type, categories: _categories),
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _entries
        .where(
          (e) =>
              _typeFilter.contains(e.contentType) &&
              _roleFilter.contains(e.authorRole),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Our Vault'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.clock),
            tooltip: 'History',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Iconsax.heart),
            tooltip: 'Favorites',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
          ),
          IconButton(
            icon: const Icon(Iconsax.sms_notification),
            tooltip: 'Approvals',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConsentRequestsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Iconsax.setting_2),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNew,
        child: const Icon(Iconsax.add),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: CountdownCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterPill(
                  label: 'টেক্সট',
                  icon: Iconsax.document_text,
                  color: AppColors.halalGreen,
                  selected: _typeFilter.contains('text'),
                  onTap: () => _toggleFilter(_typeFilter, 'text'),
                ),
                _FilterPill(
                  label: 'ছবি',
                  icon: Iconsax.image,
                  color: AppColors.halalGreen,
                  selected: _typeFilter.contains('photo'),
                  onTap: () => _toggleFilter(_typeFilter, 'photo'),
                ),
                _FilterPill(
                  label: 'ভিডিও',
                  icon: Iconsax.video,
                  color: AppColors.halalGreen,
                  selected: _typeFilter.contains('video'),
                  onTap: () => _toggleFilter(_typeFilter, 'video'),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.grey.withValues(alpha: 0.3),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                ),
                _FilterPill(
                  label: 'স্বামী',
                  icon: Iconsax.man,
                  color: AppColors.husband,
                  selected: _roleFilter.contains('husband'),
                  onTap: () => _toggleFilter(_roleFilter, 'husband'),
                ),
                _FilterPill(
                  label: 'স্ত্রী',
                  icon: Iconsax.woman,
                  color: AppColors.wife,
                  selected: _roleFilter.contains('wife'),
                  onTap: () => _toggleFilter(_roleFilter, 'wife'),
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
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EntryDetailScreen(entryId: list[i].id),
                              ),
                            );
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

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : Colors.grey.withValues(alpha: 0.35),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? color : Colors.grey),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? color : Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
