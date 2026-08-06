import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_provider.dart';
import '../services/social_service.dart';
import 'author_badge.dart';
import 'comment_section.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

Future<void> openCommentThread(
  BuildContext context,
  String targetType,
  String targetId, {
  VoidCallback? onClosed,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SizedBox(
        height: 420,
        child: SingleChildScrollView(
          child: CommentSection(targetType: targetType, targetId: targetId),
        ),
      ),
    ),
  );
  onClosed?.call();
}

/// Just the "💬 N comments" icon+count, tappable to open the full thread --
/// meant to sit inline in a compact action row alongside the reaction and
/// view-count icons (see `VaultEntryCard`). Separated from [CommentPreview]
/// (the actual preview lines) so the two can be laid out independently.
class CommentCountButton extends StatefulWidget {
  final String targetType;
  final String targetId;
  final VoidCallback? onChanged;
  const CommentCountButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.onChanged,
  });

  @override
  State<CommentCountButton> createState() => CommentCountButtonState();
}

class CommentCountButtonState extends State<CommentCountButton> {
  int _count = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final vmk = context.read<SessionProvider>().vmk!;
    try {
      final comments = await SocialService().listComments(
        vmk,
        widget.targetType,
        widget.targetId,
      );
      if (mounted) setState(() => _count = comments.length);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openCommentThread(
        context,
        widget.targetType,
        widget.targetId,
        onClosed: () {
          reload();
          widget.onChanged?.call();
        },
      ),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.message_2, size: 18, color: Colors.grey),
            if (!_loading && _count > 0) ...[
              const SizedBox(width: 4),
              Text('$_count', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows up to the 2 most recent comments directly under a post, with no
/// click needed. Tapping any line opens the full thread. [showHeader]
/// controls whether the "মন্তব্য করুন"/"Nটি মন্তব্য" header row renders --
/// off when a [CommentCountButton] elsewhere already covers that (see
/// `VaultEntryCard`'s combined action row), on for standalone use. See
/// DECISIONS.md.
class CommentPreview extends StatefulWidget {
  final String targetType;
  final String targetId;
  final bool showHeader;
  const CommentPreview({
    super.key,
    required this.targetType,
    required this.targetId,
    this.showHeader = true,
  });

  @override
  State<CommentPreview> createState() => CommentPreviewState();
}

class CommentPreviewState extends State<CommentPreview> {
  List<CommentModel> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final vmk = context.read<SessionProvider>().vmk!;
    try {
      final comments = await SocialService().listComments(
        vmk,
        widget.targetType,
        widget.targetId,
      );
      if (mounted) {
        setState(() {
          _comments = comments;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openFullThread() => openCommentThread(
    context,
    widget.targetType,
    widget.targetId,
    onClosed: reload,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final masked = context.watch<SessionProvider>().privacyMask;
    final preview = _comments.length > 2
        ? _comments.sublist(_comments.length - 2)
        : _comments;
    if (!widget.showHeader && preview.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeader)
          InkWell(
            onTap: _openFullThread,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Iconsax.message_2, size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    _comments.isEmpty ? 'মন্তব্য করুন' : '${_comments.length}টি মন্তব্য',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        for (final c in preview)
          GestureDetector(
            onTap: _openFullThread,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuthorAvatar(role: c.authorRole, radius: 10),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      masked ? '● ● ●' : (c.decryptedText ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
