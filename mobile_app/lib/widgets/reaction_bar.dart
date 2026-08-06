import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/social_service.dart';
import 'author_badge.dart';
import 'match_celebration_overlay.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// One row per person who's reacted -- their avatar, then all their emoji
/// stuck together with no per-emoji counts (multiple different emoji from
/// the same person is the whole point now, so a count next to each one
/// would be noise). Tapping an emoji in your own row removes it.
///
/// Split into [ReactionList] (just the rows above) and [ReactionAddButton]
/// (just the add-emoji icon) so screens that want the icon sitting inline
/// in their own compact action row (see `VaultEntryCard`) can use that
/// piece alone; [ReactionBar] itself just stacks both, unchanged, for
/// places (Reel) that show the full thing as one block. See DECISIONS.md.
class ReactionBar extends StatelessWidget {
  final String targetType;
  final String targetId;
  const ReactionBar({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ReactionList(targetType: targetType, targetId: targetId),
        ReactionAddButton(targetType: targetType, targetId: targetId),
      ],
    );
  }
}

class ReactionList extends StatefulWidget {
  final String targetType;
  final String targetId;
  const ReactionList({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  State<ReactionList> createState() => ReactionListState();
}

class ReactionListState extends State<ReactionList> {
  final _service = SocialService();
  List<ReactionPersonGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final groups = await _service.getReactionBreakdown(
        widget.targetType,
        widget.targetId,
      );
      if (mounted) {
        setState(() {
          _groups = groups;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeMine(String emoji) async {
    await _service.removeReaction(widget.targetType, widget.targetId, emoji);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _groups
          .map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuthorAvatar(role: g.role, radius: 10),
                  const SizedBox(width: 6),
                  ...g.emojis.map(
                    (e) => GestureDetector(
                      onTap: g.isMe ? () => _removeMine(e) : null,
                      child: Text(e, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Just the add-emoji icon -- opens the same sheet as before. Takes an
/// optional [onChanged] so a parent showing a separate [ReactionList] (or
/// its own count) can refresh once a reaction is added, since this button
/// no longer owns that state itself.
class ReactionAddButton extends StatelessWidget {
  final String targetType;
  final String targetId;
  final VoidCallback? onChanged;
  final double size;
  const ReactionAddButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.onChanged,
    this.size = 20,
  });

  Future<void> _addEmoji(BuildContext context, String emoji) async {
    final service = SocialService();
    final matched = await service.addReaction(targetType, targetId, emoji);
    if (matched && context.mounted) showMatchCelebration(context);
    onChanged?.call();
  }

  /// Opens the phone's own keyboard (with its built-in emoji panel -- most
  /// keyboards, e.g. Gboard, have a smiley key right next to the text
  /// entry) so ANY emoji can be picked. Stays open after each add so
  /// several different emoji can be added one after another. See
  /// DECISIONS.md.
  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddEmojiSheet(onAdd: (e) => _addEmoji(context, e)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Icon(Iconsax.emoji_happy, size: size, color: Colors.grey),
      ),
    );
  }
}

// Typing an emoji via the keyboard is slow -- these common ones can be
// added with a single tap instead. See DECISIONS.md.
const _kCommonEmojis = ['❤️', '😍', '😂', '😮', '😢', '👍', '🥰', '🔥'];

class _AddEmojiSheet extends StatefulWidget {
  final Future<void> Function(String emoji) onAdd;
  const _AddEmojiSheet({required this.onAdd});

  @override
  State<_AddEmojiSheet> createState() => _AddEmojiSheetState();
}

class _AddEmojiSheetState extends State<_AddEmojiSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await widget.onAdd(text);
    _controller.clear();
    if (mounted) {
      setState(() => _sending = false);
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'রিয়্যাক্ট করুন',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'একটাতে ট্যাপ করলেই সাথে সাথে যোগ হবে, অথবা নিচে লিখে কিবোর্ডের ইমোজি বাটন দিয়ে যেকোনো ইমোজি বাছাই করুন -- একের পর এক একাধিক ইমোজি দিয়ে রিয়্যাক্ট করা যাবে।',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _kCommonEmojis
                .map(
                  (e) => InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _sending ? null : () => widget.onAdd(e),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28),
                  decoration: const InputDecoration(hintText: '😊'),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Iconsax.tick_circle),
                onPressed: _sending ? null : _submit,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('শেষ হয়েছে'),
            ),
          ),
        ],
      ),
    );
  }
}
