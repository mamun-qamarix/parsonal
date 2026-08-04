import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../services/reel_service.dart';
import '../../widgets/comment_section.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/match_celebration_overlay.dart';
import '../../widgets/reaction_bar.dart';

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
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  void _maybeShowMatch(int index) {
    if (_celebrated.contains(index)) return;
    if (_items[index].isMatch) {
      _celebrated.add(index);
      WidgetsBinding.instance.addPostFrameCallback((_) => showMatchCelebration(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.halalGreen))
            : _items.isEmpty
                ? const Center(child: Text('No photos or videos yet', style: TextStyle(color: Colors.white)))
                : PageView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: _items.length,
                    onPageChanged: _maybeShowMatch,
                    itemBuilder: (context, i) => _ReelPage(item: _items[i]),
                  ),
      ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: _favoritesOnly ? Colors.redAccent : Colors.white24,
        onPressed: () {
          setState(() => _favoritesOnly = !_favoritesOnly);
          _load();
        },
        child: const Icon(Icons.favorite, color: Colors.white),
      ),
    );
  }
}

class _ReelPage extends StatelessWidget {
  final ReelItem item;
  const _ReelPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final asset = entry.mediaAssets.isNotEmpty ? entry.mediaAssets.first : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (asset != null)
          entry.contentType == 'video' ? DecryptedVideoPlayer(assetId: asset.id) : DecryptedFullImage(assetId: asset.id)
        else
          const ColoredBox(color: Colors.black),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: entry.authorRole == 'husband' ? AppColors.husband : AppColors.wife,
                    child: Icon(entry.authorRole == 'husband' ? Icons.man : Icons.woman, size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(entry.authorRole, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  if (item.isMatch) ...[const SizedBox(width: 8), const Text('💚 match', style: TextStyle(color: AppColors.halalGreenDark))],
                ],
              ),
              if ((entry.decryptedText ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(entry.decryptedText!, style: const TextStyle(color: Colors.white)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white)),
                      child: ReactionBar(targetType: 'vault_entry', targetId: entry.id),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.mode_comment_outlined, color: Colors.white),
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => Padding(
                        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
                        child: SizedBox(height: 400, child: SingleChildScrollView(child: CommentSection(targetType: 'vault_entry', targetId: entry.id))),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
