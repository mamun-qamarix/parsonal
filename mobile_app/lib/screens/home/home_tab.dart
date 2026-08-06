import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/vault_service.dart';
import '../../widgets/countdown_card.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/vault_entry_card.dart';
import '../favorites/favorites_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';
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
  // null = "সব" -- the default for all three filter rows. Single-select,
  // not multi-select: previously every individual pill stayed visually
  // "selected" alongside "সব" itself, which read as cluttered/wrong.
  // Tapping "সব" clears back to showing everything; tapping any specific
  // pill filters to exactly that one. See DECISIONS.md.
  String? _typeFilter;
  String? _roleFilter;
  String? _categoryFilter;

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
    final entries = results[0] as List<VaultEntry>;
    entries.shuffle(); // fresh random order on every refresh, per request
    setState(() {
      _entries = entries;
      _categories = results[1] as List<Category>;
      _loading = false;
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
    final session = context.watch<SessionProvider>();
    final list = _entries
        .where(
          (e) =>
              (_typeFilter == null || e.contentType == _typeFilter) &&
              (_roleFilter == null || e.authorRole == _roleFilter) &&
              (_categoryFilter == null || e.categoryId == _categoryFilter),
        )
        .toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _createNew,
        child: const Icon(Iconsax.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // Just the title bar -- floating+snap so it comes right back on
            // the very next scroll-up gesture. The countdown/filter block
            // below is a *separate*, non-floating sliver on purpose: it
            // scrolls away normally with the rest of the content and only
            // reappears once you've actually scrolled back near the top,
            // instead of snapping back together with the app bar on every
            // small upward scroll. See DECISIONS.md.
            SliverAppBar(
              floating: true,
              snap: true,
              title: Row(
                children: [
                  Icon(Iconsax.heart_copy, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('পার্সোনাল'),
                ],
              ),
              actions: [
                const NotificationBell(),
                IconButton(
                  icon: const Icon(Iconsax.clock),
                  tooltip: 'হিস্টরি',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Iconsax.heart),
                  tooltip: 'ফেভারিট',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                  ),
                ),
                IconButton(
                  icon: Icon(session.privacyMask ? Iconsax.eye_slash : Iconsax.eye),
                  tooltip: session.privacyMask
                      ? 'সবকিছু আবার দেখান'
                      : 'পুরো অ্যাপে ছবি ঝাপসা করুন, টেক্সট ও নাম লুকান',
                  onPressed: session.togglePrivacyMask,
                ),
                IconButton(
                  icon: const Icon(Iconsax.setting_2),
                  tooltip: 'সেটিংস',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: CountdownCard(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _FilterPill(
                            label: 'সব',
                            icon: Iconsax.category,
                            color: Theme.of(context).colorScheme.primary,
                            selected: _typeFilter == null,
                            onTap: () => setState(() => _typeFilter = null),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'টেক্সট',
                            icon: Iconsax.document_text,
                            color: Theme.of(context).colorScheme.primary,
                            selected: _typeFilter == 'text',
                            onTap: () => setState(() => _typeFilter = 'text'),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'ছবি',
                            icon: Iconsax.image,
                            color: Theme.of(context).colorScheme.primary,
                            selected: _typeFilter == 'photo',
                            onTap: () => setState(() => _typeFilter = 'photo'),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'ভিডিও',
                            icon: Iconsax.video,
                            color: Theme.of(context).colorScheme.primary,
                            selected: _typeFilter == 'video',
                            onTap: () => setState(() => _typeFilter = 'video'),
                          ),
                          Container(
                            width: 1,
                            height: 28,
                            color: Colors.grey.withValues(alpha: 0.3),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _FilterPill(
                            label: 'সব',
                            icon: Iconsax.category,
                            color: Theme.of(context).colorScheme.primary,
                            selected: _roleFilter == null,
                            onTap: () => setState(() => _roleFilter = null),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'স্বামী',
                            icon: Iconsax.man,
                            color: AppColors.husband,
                            selected: _roleFilter == 'husband',
                            onTap: () => setState(() => _roleFilter = 'husband'),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'স্ত্রী',
                            icon: Iconsax.woman,
                            color: AppColors.wife,
                            selected: _roleFilter == 'wife',
                            onTap: () => setState(() => _roleFilter = 'wife'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_categories.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _FilterPill(
                              label: 'সব',
                              icon: Iconsax.category,
                              color: Theme.of(context).colorScheme.primary,
                              selected: _categoryFilter == null,
                              onTap: () => setState(() => _categoryFilter = null),
                            ),
                            for (final c in _categories) ...[
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: session.privacyMask
                                    ? '●●●'
                                    : (c.decryptedName ?? '...'),
                                icon: Iconsax.tag,
                                color: Theme.of(context).colorScheme.primary,
                                selected: _categoryFilter == c.id,
                                onTap: () => setState(() => _categoryFilter = c.id),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_loading)
              const SliverFillRemaining(child: ShimmerFeedList())
            else if (list.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('এখনো কিছু নেই')),
              )
            else
              // Full-bleed, edge-to-edge -- no per-card box/margin anymore,
              // a thin divider between posts does the separating instead.
              // See DECISIONS.md.
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Column(
                    children: [
                      VaultEntryCard(
                        entry: list[i],
                        onChanged: _load,
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
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                    ],
                  ),
                  childCount: list.length,
                ),
              ),
          ],
        ),
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
            width: 0.75,
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
