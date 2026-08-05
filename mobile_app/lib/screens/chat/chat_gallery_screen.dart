import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/chat_service.dart';
import '../../services/vault_service.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/shimmer_loading.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Every photo/video ever exchanged in chat, in one grid -- previously the
/// only way to find an old chat photo again was scrolling back through the
/// whole conversation. Tap a thumbnail to view it full-screen (zoomable);
/// tap "পোস্ট করুন" to also publish that same image/video to the home
/// feed as a new vault entry, reusing the already-uploaded media asset
/// rather than re-uploading it. See DECISIONS.md.
class ChatGalleryScreen extends StatefulWidget {
  const ChatGalleryScreen({super.key});

  @override
  State<ChatGalleryScreen> createState() => _ChatGalleryScreenState();
}

class _ChatGalleryScreenState extends State<ChatGalleryScreen> {
  final _chatService = ChatService();
  List<ChatMediaItem> _items = [];
  bool _loading = true;
  final Set<String> _posting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _chatService.listMedia();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _post(ChatMediaItem item) async {
    setState(() => _posting.add(item.mediaAssetId));
    try {
      final vmk = context.read<SessionProvider>().vmk!;
      await VaultService().createEntry(
        vmk,
        contentType: item.contentType,
        text: '',
        mediaAssetIds: [item.mediaAssetId],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('হোমে পোস্ট করা হয়েছে।')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('পোস্ট করা যায়নি, আবার চেষ্টা করুন।')),
        );
      }
    } finally {
      if (mounted) setState(() => _posting.remove(item.mediaAssetId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('চ্যাট গ্যালারি')),
      body: _loading
          ? const ShimmerFeedList()
          : _items.isEmpty
          ? const Center(
              child: Text('এখনো কোনো ছবি/ভিডিও নেই', style: TextStyle(color: Colors.grey)),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                final posting = _posting.contains(item.mediaAssetId);
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaViewerScreen(
                        assetId: item.mediaAssetId,
                        contentType: item.contentType,
                      ),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecryptedThumbnail(
                        assetId: item.mediaAssetId,
                        hasThumbnail: item.hasThumbnail,
                        isVideo: item.contentType == 'video',
                      ),
                      if (item.contentType == 'video')
                        const Center(
                          child: Icon(Iconsax.play_circle_copy, color: Colors.white, size: 28),
                        ),
                      Positioned(
                        left: 4,
                        right: 4,
                        bottom: 4,
                        child: SizedBox(
                          height: 26,
                          child: ElevatedButton(
                            onPressed: posting ? null : () => _post(item),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.halalGreen.withValues(alpha: 0.9),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              textStyle: const TextStyle(fontSize: 10),
                            ),
                            child: posting
                                ? const SizedBox(
                                    height: 12,
                                    width: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('পোস্ট করুন'),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
