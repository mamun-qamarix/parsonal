import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_provider.dart';
import '../services/vault_service.dart';
import 'author_badge.dart';
import 'comment_preview.dart';
import 'decrypted_media.dart';
import 'media_viewer_screen.dart';
import 'reaction_bar.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Social-media-feed-style post: full-bleed, edge-to-edge (no boxed card
/// look -- a thin `Divider` between posts does the separating instead,
/// per request) with a full-width media block up top when there's media.
///
/// Header shows the poster's real profile photo + name (via [AuthorRow])
/// instead of a generic husband/wife label -- the filter pills above the
/// feed already separate by role, so this is about *who*, not *which
/// role*. See DECISIONS.md.
class VaultEntryCard extends StatefulWidget {
  final VaultEntry entry;
  final VoidCallback onTap;
  /// Called after an edit/delete/favorite change so the parent list can
  /// refresh itself without waiting for a full navigation round-trip.
  final VoidCallback? onChanged;
  /// Home screen's privacy toggle (see DECISIONS.md) -- blurs media and
  /// masks caption text with dots when on. Purely visual on this device;
  /// doesn't touch the actual decrypted bytes/text underneath.
  final bool privacyMask;
  const VaultEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onChanged,
    this.privacyMask = false,
  });

  @override
  State<VaultEntryCard> createState() => _VaultEntryCardState();
}

class _VaultEntryCardState extends State<VaultEntryCard> {
  late bool _favorite = widget.entry.isFavoriteMine;
  bool _busy = false;
  bool _captionExpanded = false;

  final _reactionListKey = GlobalKey<ReactionListState>();
  final _commentPreviewKey = GlobalKey<CommentPreviewState>();
  final _commentCountKey = GlobalKey<CommentCountButtonState>();

  // Media shows its own natural aspect ratio (no forced crop) up to a
  // capped max height of 2x the width -- an extremely tall image/video
  // would otherwise blow out the feed's rhythm. Starts at a plausible
  // default and updates once the real dimensions are known. See
  // DECISIONS.md.
  double _aspectRatio = 4 / 3;

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

  /// The three action affordances (add-emoji, comment, views) side by side
  /// in one compact row instead of three stacked blocks -- takes less
  /// space and reads more like a normal social feed. The actual reaction
  /// emoji / comment preview lines (if any exist) follow directly below,
  /// since those show real content rather than just being buttons.
  Widget _actionsBlock(VaultEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReactionAddButton(
              targetType: 'vault_entry',
              targetId: entry.id,
              onChanged: () => _reactionListKey.currentState?.reload(),
            ),
            const SizedBox(width: 16),
            CommentCountButton(
              key: _commentCountKey,
              targetType: 'vault_entry',
              targetId: entry.id,
              onChanged: () => _commentPreviewKey.currentState?.reload(),
            ),
            const SizedBox(width: 16),
            const Icon(Iconsax.eye, size: 16, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              '${entry.viewCount}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
        ReactionList(
          key: _reactionListKey,
          targetType: 'vault_entry',
          targetId: entry.id,
        ),
        CommentPreview(
          key: _commentPreviewKey,
          targetType: 'vault_entry',
          targetId: entry.id,
          showHeader: false,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final asset = entry.mediaAssets.isNotEmpty ? entry.mediaAssets.first : null;
    final caption = entry.decryptedText;
    final captionIsLong = (caption?.length ?? 0) > 140;
    // Only for text-only posts (no media) does the actions block move
    // below the text instead of above it -- media posts keep the action
    // row directly under the media, matching the usual social-feed order.
    final isTextOnly = asset == null;

    final captionWidget = (caption != null && caption.isNotEmpty)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.privacyMask
                  ? const Text(
                      '● ● ● ●',
                      style: TextStyle(letterSpacing: 2),
                    )
                  : Text(
                      caption,
                      maxLines: _captionExpanded ? null : 3,
                      overflow: _captionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
              if (captionIsLong && !widget.privacyMask)
                GestureDetector(
                  onTap: () =>
                      setState(() => _captionExpanded = !_captionExpanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _captionExpanded ? 'কম দেখুন' : 'আরও দেখুন',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          )
        : (asset == null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_typeIcon, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      entry.contentType,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                )
              : const SizedBox.shrink());

    return InkWell(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 0),
            child: Row(
              children: [
                AuthorRow(role: entry.authorRole),
                const Spacer(),
                Text(
                  DateFormat.MMMd().add_jm().format(entry.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
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
            GestureDetector(
              // Blurred means "don't actually let anyone tap through to
              // full-screen it either" -- the point is nothing readable
              // shows up on this screen at all right now.
              onTap: widget.privacyMask
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MediaViewerScreen(
                          assetId: asset.id,
                          contentType: entry.contentType,
                        ),
                      ),
                    ),
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ImageFiltered(
                      imageFilter: widget.privacyMask
                          ? ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22)
                          : ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                      child: DecryptedThumbnail(
                        assetId: asset.id,
                        hasThumbnail: asset.hasThumbnail,
                        isVideo: entry.contentType == 'video',
                        onAspectRatio: (r) => setState(
                          () => _aspectRatio = r < 0.5 ? 0.5 : r,
                        ),
                      ),
                    ),
                    if (entry.contentType == 'video' && !widget.privacyMask)
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
                    if (widget.privacyMask)
                      Container(
                        color: Colors.black38,
                        child: const Center(
                          child: Icon(
                            Iconsax.eye_slash,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: isTextOnly
                  ? [
                      captionWidget,
                      const SizedBox(height: 8),
                      _actionsBlock(entry),
                    ]
                  : [
                      _actionsBlock(entry),
                      const SizedBox(height: 4),
                      captionWidget,
                    ],
            ),
          ),
        ],
      ),
    );
  }
}
