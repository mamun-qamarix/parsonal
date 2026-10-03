import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../services/vault_service.dart';
import '../../widgets/decrypted_media.dart';
import '../../widgets/linkified_text.dart';
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/shimmer_loading.dart';

/// Everything that was deleted from the feed lands here and can be
/// restored. Nothing is ever purged from the server automatically, and
/// there's deliberately no "delete forever" button. See DECISIONS.md.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _service = VaultService();
  List<VaultEntry> _entries = [];
  bool _loading = true;
  String? _error;
  final Set<String> _restoring = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vmk = context.read<SessionProvider>().vmk!;
    try {
      final entries = await _service.listTrash(vmk);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'ট্র্যাশ লোড করা যায়নি। ইন্টারনেট চেক করে আবার চেষ্টা করুন।';
      });
    }
  }

  Future<void> _restore(VaultEntry entry) async {
    setState(() => _restoring.add(entry.id));
    try {
      await _service.restoreEntry(entry.id);
      if (!mounted) return;
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ফিরিয়ে আনা হয়েছে ✅ (হোম রিফ্রেশ করলে দেখা যাবে)')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ফিরিয়ে আনা যায়নি, আবার চেষ্টা করুন')),
      );
    } finally {
      if (mounted) setState(() => _restoring.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final privacyMask = context.watch<SessionProvider>().privacyMask;
    return Scaffold(
      appBar: AppBar(title: const Text('ট্র্যাশ')),
      body: _loading
          ? const ShimmerFeedList()
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(_error!)),
                      ],
                    )
                  : _entries.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('ট্র্যাশ খালি')),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _entries.length + 1,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'মুছে ফেলা ছবি/ভিডিও/লেখা এখানে সুরক্ষিত থাকে — সার্ভার থেকে কখনো মুছে যায় না। চাইলে ফিরিয়ে আনতে পারবেন।',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          );
                        }
                        return _row(_entries[i - 1], privacyMask);
                      },
                    ),
            ),
    );
  }

  Widget _row(VaultEntry entry, bool privacyMask) {
    final asset = entry.mediaAssets.isNotEmpty ? entry.mediaAssets.first : null;
    final caption = entry.decryptedText ?? '';
    final busy = _restoring.contains(entry.id);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (asset != null)
            GestureDetector(
              onTap: privacyMask
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MediaViewerScreen(
                          assetId: asset.id,
                          contentType: entry.contentType,
                        ),
                      ),
                    ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecryptedThumbnail(
                        assetId: asset.id,
                        hasThumbnail: asset.hasThumbnail,
                        isVideo: entry.contentType == 'video',
                      ),
                      if (entry.contentType == 'video' && !privacyMask)
                        const Center(
                          child: Icon(
                            Iconsax.play_circle_copy,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (asset != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMd().add_jm().format(entry.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                if (caption.isNotEmpty)
                  privacyMask
                      ? const Text('● ● ● ●')
                      : LinkifiedText(
                          caption,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        )
                else
                  Text(
                    entry.contentType == 'video'
                        ? 'ভিডিও'
                        : entry.contentType == 'photo'
                        ? 'ছবি'
                        : 'লেখা',
                    style: const TextStyle(color: Colors.grey),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _restore(entry),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Iconsax.undo, size: 16),
                    label: const Text('ফিরিয়ে আনুন'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
