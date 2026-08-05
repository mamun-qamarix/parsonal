import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/social_service.dart';
import 'match_celebration_overlay.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

const kQuickEmojis = ['❤️', '😍', '😂', '🥰', '😢', '👍'];

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
      if (mounted)
        setState(() {
          _breakdown = b;
          _loading = false;
        });
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

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 16,
          children: kQuickEmojis
              .map(
                (e) => InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _toggle(e);
                  },
                  child: Text(e, style: const TextStyle(fontSize: 32)),
                ),
              )
              .toList(),
        ),
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
          (b) => GestureDetector(
            onLongPress: _showPicker,
            child: InkWell(
              onTap: () => _toggle(b.emoji),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: b.reactedByMe
                      ? AppColors.halalGreen.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${b.emoji} ${b.husbandCount + b.wifeCount}  (H:${b.husbandCount} W:${b.wifeCount})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ),
        InkWell(
          onLongPress: _showPicker,
          onTap: () => _toggle('❤️'),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
