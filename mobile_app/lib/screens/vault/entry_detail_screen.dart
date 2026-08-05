import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/social_service.dart';
import '../../services/vault_service.dart';
import '../../widgets/comment_section.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/match_celebration_overlay.dart';
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/reaction_bar.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class EntryDetailScreen extends StatefulWidget {
  final String entryId;
  const EntryDetailScreen({super.key, required this.entryId});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  final _vaultService = VaultService();
  VaultEntry? _entry;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final entry = await _vaultService.getEntry(vmk, widget.entryId);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _loading = false;
    });
    final show = await SocialService().checkMatchCelebration(
      'vault_entry',
      widget.entryId,
    );
    if (show && mounted) showMatchCelebration(context);
  }

  Future<void> _toggleFavorite() async {
    final isFav = await _vaultService.toggleFavorite(widget.entryId);
    setState(() => _entry = _entry);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFav ? 'Added to favorites' : 'Removed from favorites',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      _load();
    }
  }

  /// Edits and deletes apply immediately -- no approval needed from the
  /// other spouse (at least for now). See DECISIONS.md.
  Future<void> _edit() async {
    final controller = TextEditingController(text: _entry?.decryptedText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('এডিট করুন'),
        content: TextField(controller: controller, maxLines: 5, autofocus: true),
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
    if (text == null || !mounted) return;
    final vmk = context.read<SessionProvider>().vmk!;
    await _vaultService.updateEntry(
      vmk,
      widget.entryId,
      text,
      categoryId: _entry?.categoryId,
    );
    if (mounted) _load();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('এন্ট্রিটা মুছে ফেলবেন?'),
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
    if (confirm != true || !mounted) return;
    await _vaultService.deleteEntry(widget.entryId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _entry == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entry = _entry!;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(
              entry.isFavoriteMine ? Iconsax.heart_copy : Iconsax.heart,
              color: entry.isFavoriteMine ? Colors.redAccent : null,
            ),
            onPressed: _toggleFavorite,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _edit();
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('এডিট করুন')),
              PopupMenuItem(value: 'delete', child: Text('মুছে ফেলুন')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text(
                  DateFormat.yMMMd().add_jm().format(entry.createdAt.toLocal()),
                ),
                const Spacer(),
                Text(
                  '${entry.viewCount} views',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (entry.mediaAssets.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: entry.contentType == 'video'
                    ? DecryptedVideoPlayer(assetId: entry.mediaAssets.first.id)
                    : GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MediaViewerScreen(
                              assetId: entry.mediaAssets.first.id,
                              contentType: 'photo',
                            ),
                          ),
                        ),
                        child: SizedBox(
                          height: 320,
                          width: double.infinity,
                          child: DecryptedFullImage(
                            assetId: entry.mediaAssets.first.id,
                            zoomable: false, // full zoom lives in MediaViewerScreen now
                          ),
                        ),
                      ),
              ),
            if (entry.decryptedText != null &&
                entry.decryptedText!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(entry.decryptedText!, style: const TextStyle(fontSize: 16)),
            ],
            const SizedBox(height: 20),
            ReactionBar(targetType: 'vault_entry', targetId: entry.id),
            const SizedBox(height: 20),
            const Divider(),
            CommentSection(targetType: 'vault_entry', targetId: entry.id),
          ],
        ),
      ),
    );
  }
}
