import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../providers/session_provider.dart';
import '../services/profile_cache.dart';
import 'decrypted_media.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Falls back to the generic role label when no name is set on that
/// profile yet. When the app-wide privacy mask is on, the real name is
/// replaced with dots too -- "everything, nothing excluded" per request.
/// See DECISIONS.md.
String authorDisplayName(String role, ProfileModel? profile, {bool masked = false}) {
  if (masked) return '● ● ●';
  final name = profile?.decryptedName;
  if (name != null && name.isNotEmpty) return name;
  return role == 'husband' ? 'স্বামী' : 'স্ত্রী';
}

/// Just the circular avatar -- the real profile photo if one's set,
/// otherwise the same role-colored fallback icon used before profiles
/// had photos. Used wherever showing a name alongside would be too much
/// (e.g. one per reaction row).
class AuthorAvatar extends StatelessWidget {
  final String role;
  final double radius;
  const AuthorAvatar({super.key, required this.role, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final vmk = context.read<SessionProvider>().vmk!;
    return FutureBuilder<ProfileModel?>(
      future: ProfileCache.instance.get(vmk, role),
      initialData: ProfileCache.instance.peek(role),
      builder: (context, snapshot) {
        final photoId = snapshot.data?.profilePhotoAssetId;
        final accent = role == 'husband' ? AppColors.husband : AppColors.wife;
        if (photoId != null) {
          return ClipOval(
            child: SizedBox(
              width: radius * 2,
              height: radius * 2,
              child: DecryptedThumbnail(assetId: photoId, hasThumbnail: false),
            ),
          );
        }
        return CircleAvatar(
          radius: radius,
          backgroundColor: accent,
          child: Icon(
            role == 'husband' ? Iconsax.man : Iconsax.woman,
            size: radius,
            color: Colors.white,
          ),
        );
      },
    );
  }
}

/// Avatar + real display name, side by side -- the standard "who did
/// this" indicator for posts and comments, replacing the old generic
/// role icon + "husband"/"wife" label. See DECISIONS.md.
class AuthorRow extends StatelessWidget {
  final String role;
  final double avatarRadius;
  final TextStyle? textStyle;
  const AuthorRow({
    super.key,
    required this.role,
    this.avatarRadius = 12,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final vmk = context.read<SessionProvider>().vmk!;
    final masked = context.watch<SessionProvider>().privacyMask;
    return FutureBuilder<ProfileModel?>(
      future: ProfileCache.instance.get(vmk, role),
      initialData: ProfileCache.instance.peek(role),
      builder: (context, snapshot) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthorAvatar(role: role, radius: avatarRadius),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                authorDisplayName(role, snapshot.data, masked: masked),
                overflow: TextOverflow.ellipsis,
                style: textStyle ?? const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}
