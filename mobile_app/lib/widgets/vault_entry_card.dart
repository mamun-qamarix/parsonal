import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_provider.dart';
import '../services/vault_service.dart';
import 'decrypted_media.dart';
import 'reaction_bar.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Social-media-feed-style post card: a full-width media block up top (like
/// a Facebook/Instagram post) instead of a small side thumbnail, so photos
/// and videos are actually easy to see while scrolling a list.
///
/// No husband/wife label or avatar on the card itself -- that's what the
/// husband/wife filter pills above the feed are for, showing it again on
/// every card was redundant. See DECISIONS.md.
class VaultEntryCard extends StatefulWidget {
  final VaultEntry entry;
  final VoidCallback onTap;
  /// Called after an edit/delete/favorite change so the parent list can
  /// refresh itself without waiting for a full navigation round-trip.
  final VoidCallback? onChanged;
  const VaultEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onChanged,
  });

  @override
  State<VaultEntryCard> createState() => _VaultEntryCardState();
}

class _VaultEntryCardState extends State<VaultEntryCard> {
  late bool _favorite = widget.entry.isFavoriteMine;
  bool _busy = false;

  Future<void> _toggleFavorite() async {
    setState(() => _busy = true);
    try {
      final result = await VaultService().toggleFavorite(widget.entry.id);
      if (mounted) setState(() => _favorite = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Edits and deletes apply immediately -- no approval needed from the
  /// other spouse (at least for now). See DECISIONS.md.
  Future<void> _edit() async {
    final controller = TextEditingController(
      text: widget.entry.decryptedText ?? '',
    );
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('এডিট করুন'),
        content: TextField(controller: controller, autofocus: true, maxLines: 5),
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
    setState(() => _busy = true);
    try {
      await VaultService().updateEntry(
        vmk,
        widget.entry.id,
        text,
        categoryId: widget.entry.categoryId,
      );
      widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    setState(() => _busy = true);
    try {
      await VaultService().deleteEntry(widget.entry.id);
      widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData get _typeIcon {
    switch (widget.entry.contentType) {
      case 'photo':
        return Iconsax.image;
      case 'video':
        return Iconsax.video;
      default:
        return Iconsax.document_text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final asset = entry.mediaAssets.isNotEmpty ? entry.mediaAssets.first : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat.yMMMd().add_jm().format(entry.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: !_busy,
                    icon: const Icon(Iconsax.more, size: 20),
                    onSelected: (v) {
                      if (v == 'favorite') _toggleFavorite();
                      if (v == 'edit') _edit();
                      if (v == 'delete') _delete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'favorite',
                        child: Text(_favorite ? 'ফেভারিট থেকে সরান' : 'ফেভারিটে যোগ করুন'),
                      ),
                      const PopupMenuItem(value: 'edit', child: Text('এডিট করুন')),
                      const PopupMenuItem(value: 'delete', child: Text('মুছে ফেলুন')),
                    ],
                  ),
                ],
              ),
            ),
            if (asset != null)
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecryptedThumbnail(
                      assetId: asset.id,
                      hasThumbnail: asset.hasThumbnail,
                      isVideo: entry.contentType == 'video',
                    ),
                    if (entry.contentType == 'video')
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Icon(
                            Iconsax.play_circle_copy,
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReactionBar(targetType: 'vault_entry', targetId: entry.id),
                  const SizedBox(height: 8),
                  if (entry.decryptedText != null &&
                      entry.decryptedText!.isNotEmpty)
                    Text(
                      entry.decryptedText!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (asset == null)
                    Row(
                      children: [
                        Icon(_typeIcon, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          entry.contentType,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Iconsax.eye, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.viewCount}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
