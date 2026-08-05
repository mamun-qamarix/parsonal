import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../providers/session_provider.dart';
import '../services/social_service.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class CommentSection extends StatefulWidget {
  final String targetType;
  final String targetId;
  const CommentSection({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final _service = SocialService();
  final _controller = TextEditingController();
  List<CommentModel> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    final comments = await _service.listComments(
      vmk,
      widget.targetType,
      widget.targetId,
    );
    if (mounted)
      setState(() {
        _comments = comments;
        _loading = false;
      });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final vmk = context.read<SessionProvider>().vmk!;
    _controller.clear();
    await _service.addComment(vmk, widget.targetType, widget.targetId, text);
    _load();
  }

  Future<void> _edit(CommentModel c) async {
    final controller = TextEditingController(text: c.decryptedText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('মন্তব্য এডিট করুন'),
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
    await _service.updateComment(vmk, c.id, text);
    _load();
  }

  Future<void> _delete(CommentModel c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('মন্তব্যটা মুছে ফেলবেন?'),
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
    await _service.deleteComment(c.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    final myRole = context.watch<SessionProvider>().role;
    final myId = context.watch<SessionProvider>().spouseId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Comments', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._comments.map(
          (c) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: c.authorRole == 'husband'
                      ? AppColors.husband
                      : AppColors.wife,
                  child: Icon(
                    c.authorRole == 'husband' ? Iconsax.man : Iconsax.woman,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(c.decryptedText ?? ''),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Iconsax.heart_copy,
                  size: 14,
                  color: c.heartedByMe ? Colors.red : Colors.grey,
                ),
                Text('${c.heartCount}', style: const TextStyle(fontSize: 11)),
                if (c.authorId == myId)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Iconsax.more, size: 16),
                    onSelected: (v) {
                      if (v == 'edit') _edit(c);
                      if (v == 'delete') _delete(c);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('এডিট করুন')),
                      PopupMenuItem(value: 'delete', child: Text('মুছে ফেলুন')),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: myRole == null
                      ? 'Add a comment'
                      : 'Comment as $myRole...',
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: const Icon(Iconsax.send, color: AppColors.halalGreen),
              onPressed: _send,
            ),
          ],
        ),
      ],
    );
  }
}
