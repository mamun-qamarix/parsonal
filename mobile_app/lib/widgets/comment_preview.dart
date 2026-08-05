import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/session_provider.dart';
import '../services/social_service.dart';
import 'author_badge.dart';
import 'comment_section.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Shows up to the 2 most recent comments directly under a post, with no
/// click needed -- previously comments were only visible after opening
/// the entry's own detail screen. Tapping the header opens the full
/// comment thread (to add a new one or read all of them) in a bottom
/// sheet, same pattern as Reel already uses. See DECISIONS.md.
class CommentPreview extends StatefulWidget {
  final String targetType;
  final String targetId;
  const CommentPreview({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  State<CommentPreview> createState() => _CommentPreviewState();
}

class _CommentPreviewState extends State<CommentPreview> {
  List<CommentModel> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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

  Future<void> _openFullThread() async {
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
            child: CommentSection(
              targetType: widget.targetType,
              targetId: widget.targetId,
            ),
          ),
        ),
      ),
    );
    _load(); // pick up anything added while the sheet was open
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 20);
    final preview = _comments.length > 2
        ? _comments.sublist(_comments.length - 2)
        : _comments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AuthorAvatar(role: c.authorRole, radius: 10),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    c.decryptedText ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
