import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import 'decrypted_media.dart';

class VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final VoidCallback onTap;
  const VaultEntryCard({super.key, required this.entry, required this.onTap});

  IconData get _icon {
    switch (entry.contentType) {
      case 'photo':
        return Icons.image_outlined;
      case 'video':
        return Icons.videocam_outlined;
      default:
        return Icons.notes_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = entry.mediaAssets.isNotEmpty;
    final canShowThumb = hasMedia && (entry.contentType == 'photo' || entry.mediaAssets.first.hasThumbnail);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canShowThumb)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: DecryptedThumbnail(assetId: entry.mediaAssets.first.id, hasThumbnail: entry.mediaAssets.first.hasThumbnail),
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: AppColors.halalGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(_icon, color: AppColors.halalGreen),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 8,
                          backgroundColor: entry.authorRole == 'husband' ? AppColors.husband : AppColors.wife,
                          child: Icon(entry.authorRole == 'husband' ? Icons.man : Icons.woman, size: 10, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        Text(DateFormat.yMMMd().add_jm().format(entry.createdAt.toLocal()), style: Theme.of(context).textTheme.bodySmall),
                        const Spacer(),
                        if (entry.isFavoriteMine) const Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.contentType == 'text' ? (entry.decryptedText ?? '') : (entry.contentType == 'photo' ? 'Photo' : 'Video'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text('${entry.viewCount} views', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
