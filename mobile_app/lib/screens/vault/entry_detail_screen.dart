import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/media/video_clip_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/social_service.dart';
import '../../services/vault_service.dart';
import '../../widgets/comment_section.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/match_celebration_overlay.dart';
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

  Future<void> _handleTrimRequested(String localVideoPath) async {
    final entry = _entry;
    if (entry == null) return;
    final vmk = context.read<SessionProvider>().vmk!;
    await handleVideoTrimRequested(
      context,
      localVideoPath: localVideoPath,
      vmk: vmk,
      categoryId: entry.categoryId,
    );
  }

  Future<void> _requestEdit() async {
    final controller = TextEditingController(text: _entry?.decryptedText ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request an edit'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send for approval'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final vmk = context.read<SessionProvider>().vmk!;
    await _vaultService.requestEdit(
      vmk,
      widget.entryId,
      controller.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Edit request sent — waiting for your spouse\'s approval.',
          ),
        ),
      );
    }
  }

  Future<void> _requestDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request deletion'),
        content: const Text(
          'This will ask your spouse to approve deleting this entry. It stays until they do.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _vaultService.requestDelete(widget.entryId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Delete request sent — waiting for your spouse\'s approval.',
          ),
        ),
      );
    }
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
              if (v == 'edit') _requestEdit();
              if (v == 'delete') _requestDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Request edit')),
              PopupMenuItem(value: 'delete', child: Text('Request delete')),
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
                CircleAvatar(
                  backgroundColor: entry.authorRole == 'husband'
                      ? AppColors.husband
                      : AppColors.wife,
                  child: Icon(
                    entry.authorRole == 'husband' ? Iconsax.man : Iconsax.woman,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
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
                    ? DecryptedVideoPlayer(
                        assetId: entry.mediaAssets.first.id,
                        onTrimRequested: _handleTrimRequested,
                      )
                    : SizedBox(
                        height: 320,
                        width: double.infinity,
                        child: DecryptedFullImage(
                          assetId: entry.mediaAssets.first.id,
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
