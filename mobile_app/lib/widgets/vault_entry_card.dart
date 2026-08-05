import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/vault_service.dart';
import 'decrypted_media.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Social-media-feed-style post card: a full-width media block up top (like
/// a Facebook/Instagram post) instead of a small side thumbnail, so photos
/// and videos are actually easy to see while scrolling a list.
class VaultEntryCard extends StatefulWidget {
  final VaultEntry entry;
  final VoidCallback onTap;
  const VaultEntryCard({super.key, required this.entry, required this.onTap});

  @override
  State<VaultEntryCard> createState() => _VaultEntryCardState();
}

class _VaultEntryCardState extends State<VaultEntryCard> {
  late bool _favorite = widget.entry.isFavoriteMine;
  bool _busy = false;

  Future<void> _toggleFavorite() async {
    setState(() => _busy = true);
    try {
      final result = await VaultService().toggleFavorite(widget.entry.id);
      if (mounted) setState(() => _favorite = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData get _typeIcon {
    switch (widget.entry.contentType) {
      case 'photo':
        return Iconsax.image;
      case 'video':
        return Iconsax.video;
      default:
        return Iconsax.document_text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final asset = entry.mediaAssets.isNotEmpty ? entry.mediaAssets.first : null;
    final accent = entry.authorRole == 'husband'
        ? AppColors.husband
        : AppColors.wife;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: accent,
                    child: Icon(
                      entry.authorRole == 'husband'
                          ? Iconsax.man
                          : Iconsax.woman,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.authorRole == 'husband' ? 'স্বামী' : 'স্ত্রী',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          DateFormat.yMMMd().add_jm().format(
                            entry.createdAt.toLocal(),
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : _toggleFavorite,
                    icon: Icon(
                      _favorite ? Iconsax.heart_copy : Iconsax.heart,
                      color: _favorite ? Colors.redAccent : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (asset != null)
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecryptedThumbnail(
                      assetId: asset.id,
                      hasThumbnail: asset.hasThumbnail,
                      isVideo: entry.contentType == 'video',
                    ),
                    if (entry.contentType == 'video')
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Icon(
                            Iconsax.play_circle_copy,
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.decryptedText != null &&
                      entry.decryptedText!.isNotEmpty)
                    Text(
                      entry.decryptedText!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (asset == null)
                    Row(
                      children: [
                        Icon(_typeIcon, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          entry.contentType,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Iconsax.eye, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.viewCount}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
