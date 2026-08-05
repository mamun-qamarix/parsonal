import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/biometric_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/phrase_service.dart';
import '../../widgets/comment_section.dart';
import '../../widgets/reaction_bar.dart';
import '../../widgets/shimmer_loading.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Opens the phrases screen, but only after a fresh fingerprint/biometric
/// check every single time -- unlike the rest of the app, this doesn't
/// piggyback on the hourly password window at all, since this is
/// specifically the couple's most intimate content. See DECISIONS.md.
Future<void> openPhrasesScreen(BuildContext context) async {
  final ok = await BiometricService.authenticate(
    reason: 'প্রিয় লাইন দেখতে যাচাই করুন',
  );
  if (!ok || !context.mounted) return;
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const PhrasesScreen()));
}

class PhrasesScreen extends StatefulWidget {
  const PhrasesScreen({super.key});

  @override
  State<PhrasesScreen> createState() => _PhrasesScreenState();
}

class _PhrasesScreenState extends State<PhrasesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _service = PhraseService();
  bool _sortByRating = false;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('আমাদের প্রিয় লাইন'),
        actions: [
          IconButton(
            icon: Icon(_sortByRating ? Iconsax.star_copy : Iconsax.star),
            tooltip: 'রেটিং অনুযায়ী সাজান',
            onPressed: () => setState(() => _sortByRating = !_sortByRating),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'স্বামী → স্ত্রী'),
            Tab(text: 'স্ত্রী → স্বামী'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _PhraseList(
            direction: 'husband_to_wife',
            sortByRating: _sortByRating,
          ),
          _PhraseList(
            direction: 'wife_to_husband',
            sortByRating: _sortByRating,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final direction = _tab.index == 0
              ? 'husband_to_wife'
              : 'wife_to_husband';
          await _addPhrase(context, direction);
          setState(() {});
        },
        child: const Icon(Iconsax.add),
      ),
    );
  }

  Future<void> _addPhrase(BuildContext context, String direction) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('একটা লাইন যোগ করুন'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    final vmk = context.read<SessionProvider>().vmk!;
    await _service.create(vmk, direction, text);
  }
}

class _PhraseList extends StatefulWidget {
  final String direction;
  final bool sortByRating;
  const _PhraseList({required this.direction, required this.sortByRating});

  @override
  State<_PhraseList> createState() => _PhraseListState();
}

class _PhraseListState extends State<_PhraseList> {
  final _service = PhraseService();
  List<PhraseModel> _phrases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PhraseList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sortByRating != widget.sortByRating) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vmk = context.read<SessionProvider>().vmk!;
    final phrases = await _service.list(
      vmk,
      direction: widget.direction,
      sortByRating: widget.sortByRating,
    );
    if (mounted)
      setState(() {
        _phrases = phrases;
        _loading = false;
      });
  }

  Future<void> _rate(PhraseModel p, int rating) async {
    await _service.rate(p.id, rating);
    _load();
  }

  Future<void> _edit(PhraseModel p) async {
    final controller = TextEditingController(text: p.decryptedText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('লাইনটা এডিট করুন'),
        content: TextField(controller: controller, autofocus: true, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    final vmk = context.read<SessionProvider>().vmk!;
    await _service.update(vmk, p.id, text);
    _load();
  }

  Future<void> _delete(PhraseModel p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('লাইনটা মুছে ফেলবেন?'),
        content: const Text('এটা আর ফেরত আনা যাবে না।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.delete(p.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final myRole = context.watch<SessionProvider>().role;
    final myId = context.watch<SessionProvider>().spouseId;
    if (_loading) return const ShimmerTileList();
    if (_phrases.isEmpty) return const Center(child: Text('এখনো কিছু নেই'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _phrases.length,
        itemBuilder: (context, i) {
          final p = _phrases[i];
          final myRating = myRole == 'husband' ? p.ratingHusband : p.ratingWife;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          p.decryptedText ?? '',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      if (p.authorId == myId)
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Iconsax.more, size: 18),
                          onSelected: (v) {
                            if (v == 'edit') _edit(p);
                            if (v == 'delete') _delete(p);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('এডিট করুন')),
                            PopupMenuItem(value: 'delete', child: Text('মুছে ফেলুন')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Iconsax.man,
                        size: 16,
                        color: p.ratingHusband != null
                            ? AppColors.husband
                            : Colors.grey,
                      ),
                      Text(' ${p.ratingHusband ?? '-'}  '),
                      Icon(
                        Iconsax.woman,
                        size: 16,
                        color: p.ratingWife != null
                            ? AppColors.wife
                            : Colors.grey,
                      ),
                      Text(' ${p.ratingWife ?? '-'}'),
                      const Spacer(),
                      ...List.generate(
                        5,
                        (idx) => IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 18,
                          icon: Icon(
                            idx < (myRating ?? 0)
                                ? Iconsax.star_copy
                                : Iconsax.star,
                            color: Colors.amber,
                          ),
                          onPressed: () => _rate(p, idx + 1),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  ReactionBar(targetType: 'phrase', targetId: p.id),
                  const SizedBox(height: 8),
                  CommentSection(targetType: 'phrase', targetId: p.id),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
