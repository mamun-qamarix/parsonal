import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/reel_service.dart';
import '../../widgets/author_badge.dart';
import '../../widgets/comment_section.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/match_celebration_overlay.dart';
import '../../widgets/reaction_bar.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class ReelScreen extends StatefulWidget {
  const ReelScreen({super.key});

  @override
  State<ReelScreen> createState() => _ReelScreenState();
}

class _ReelScreenState extends State<ReelScreen> {
  final _service = ReelService();
  List<ReelItem> _items = [];
  bool _loading = true;
  bool _favoritesOnly = false;
  final Set<int> _celebrated = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vmk = context.read<SessionProvider>().vmk!;
    final items = await _service.getFeed(vmk, favoritesOnly: _favoritesOnly);
    if (mounted)
      setState(() {
        _items = items;
        _loading = false;
      });
  }

  void _maybeShowMatch(int index) {
    if (_celebrated.contains(index)) return;
    if (_items[index].isMatch) {
      _celebrated.add(index);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showMatchCelebration(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.halalGreen),
              )
            : _items.isEmpty
            ? const Center(
                child: Text(
                  'এখনো কোনো ছবি বা ভিডিও নেই',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: _items.length,
                onPageChanged: _maybeShowMatch,
                itemBuilder: (context, i) => _ReelPage(
                  item: _items[i],
                  favoritesOnly: _favoritesOnly,
                  onToggleFavoritesOnly: () {
                    setState(() => _favoritesOnly = !_favoritesOnly);
                    _load();
                  },
                ),
              ),
      ),
    );
  }
}

class _ReelPage extends StatelessWidget {
  final ReelItem item;
  final bool favoritesOnly;
  final VoidCallback onToggleFavoritesOnly;
  const _ReelPage({
    required this.item,
    required this.favoritesOnly,
    required this.onToggleFavoritesOnly,
  });

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final asset = entry.mediaAssets.isNotEmpty ? entry.mediaAssets.first : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Always full-bleed black behind the media -- StackFit.expand gives
        // every child here a TIGHT full-screen box, which used to force
        // both the video's AspectRatio and the image to stretch to fill
        // it, breaking landscape content. Width stays fixed to the screen;
        // height follows the real aspect ratio, and whatever's left shows
        // this black background instead of distorting the media. See
        // DECISIONS.md.
        const ColoredBox(color: Colors.black),
        if (asset != null)
          entry.contentType == 'video'
              ? Center(
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width,
                    child: DecryptedVideoPlayer(assetId: asset.id),
                  ),
                )
              : DecryptedFullImage(
                  assetId: asset.id,
                  fit: BoxFit.fitWidth,
                  zoomable: false,
                ),
        // Caption block, bottom-left -- leaves the right edge clear for the
        // vertical action column below so nothing overlaps. See DECISIONS.md.
        Positioned(
          left: 16,
          right: 76,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AuthorRow(
                    role: entry.authorRole,
                    avatarRadius: 12,
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.isMatch) ...[
                    const SizedBox(width: 8),
                    const Text(
                      '💚 match',
                      style: TextStyle(color: AppColors.halalGreenDark),
                    ),
                  ],
                ],
              ),
              if ((entry.decryptedText ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry.decryptedText!,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white),
                ),
                child: ReactionBar(targetType: 'vault_entry', targetId: entry.id),
              ),
            ],
          ),
        ),
        // Instagram-style vertical action column on the right -- previously
        // the comment button (bottom overlay) and the favorites-only toggle
        // (a separately-positioned FloatingActionButton) sat on top of each
        // other in the same bottom-right corner. See DECISIONS.md.
        Positioned(
          right: 12,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReelActionButton(
                icon: Iconsax.heart_copy,
                color: favoritesOnly ? Colors.redAccent : Colors.white,
                tooltip: favoritesOnly ? 'সব দেখান' : 'শুধু ফেভারিট দেখান',
                onTap: onToggleFavoritesOnly,
              ),
              const SizedBox(height: 18),
              _ReelActionButton(
                icon: Iconsax.message_2,
                color: Colors.white,
                tooltip: 'মন্তব্য',
                onTap: () => showModalBottomSheet(
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
                      height: 400,
                      child: SingleChildScrollView(
                        child: CommentSection(
                          targetType: 'vault_entry',
                          targetId: entry.id,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReelActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _ReelActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 28),
    );
  }
}
