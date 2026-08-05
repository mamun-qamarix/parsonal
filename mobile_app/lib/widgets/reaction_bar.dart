import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/social_service.dart';
import 'match_celebration_overlay.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class ReactionBar extends StatefulWidget {
  final String targetType;
  final String targetId;
  const ReactionBar({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  final _service = SocialService();
  List<ReactionBreakdown> _breakdown = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await _service.getReactionBreakdown(
        widget.targetType,
        widget.targetId,
      );
      if (mounted) {
        setState(() {
          _breakdown = b;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String emoji) async {
    final existing = _breakdown.where((b) => b.emoji == emoji).firstOrNull;
    if (existing != null && existing.reactedByMe) {
      await _service.removeReaction(widget.targetType, widget.targetId, emoji);
    } else {
      final matched = await _service.addReaction(
        widget.targetType,
        widget.targetId,
        emoji,
      );
      if (matched && mounted) {
        showMatchCelebration(context);
      }
    }
    await _load();
  }

  /// Opens the phone's own keyboard (with its built-in emoji panel -- most
  /// keyboards, e.g. Gboard, have a smiley key right next to the text
  /// entry) so ANY emoji can be picked, not just a small fixed preset set.
  /// Stays open after each add so several different emoji can be added
  /// one after another without reopening it each time. See DECISIONS.md.
  void _openAddEmoji() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddEmojiSheet(
        onAdd: (emoji) async {
          await _toggle(emoji);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 32);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ..._breakdown.map(
          (b) => InkWell(
            onTap: () => _toggle(b.emoji),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: b.reactedByMe
                    ? AppColors.halalGreen.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${b.emoji} ${b.husbandCount + b.wifeCount}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
        InkWell(
          onTap: _openAddEmoji,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(Iconsax.emoji_happy, size: 18),
          ),
        ),
      ],
    );
  }
}

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
            'কিবোর্ডের ইমোজি বাটন দিয়ে যেকোনো ইমোজি বাছাই করুন -- একের পর এক একাধিক ইমোজি দিয়ে রিয়্যাক্ট করা যাবে।',
            style: TextStyle(fontSize: 12, color: Colors.grey),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
