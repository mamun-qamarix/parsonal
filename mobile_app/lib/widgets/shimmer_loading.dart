import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Theme-aware shimmer wrapper -- base/highlight colors adapt to light/dark
/// so the effect stays subtle instead of glaring in dark mode.
class AppShimmer extends StatelessWidget {
  final Widget child;
  const AppShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF23302A) : const Color(0xFFE6EFE9),
      highlightColor: isDark
          ? const Color(0xFF344338)
          : const Color(0xFFF6FAF7),
      child: child,
    );
  }
}

class _Block extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius radius;
  const _Block({
    this.width,
    required this.height,
    this.radius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: radius),
    );
  }
}

/// Skeleton for a social-media-style feed card (big media block, author
/// row, caption lines) -- matches [VaultEntryCard]'s layout.
class ShimmerFeedCard extends StatelessWidget {
  const ShimmerFeedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const _Block(
                    width: 32,
                    height: 32,
                    radius: BorderRadius.all(Radius.circular(16)),
                  ),
                  const SizedBox(width: 10),
                  _Block(
                    width: MediaQuery.of(context).size.width * 0.3,
                    height: 12,
                  ),
                ],
              ),
            ),
            const _Block(
              width: double.infinity,
              height: 220,
              radius: BorderRadius.zero,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Block(
                    width: MediaQuery.of(context).size.width * 0.6,
                    height: 12,
                  ),
                  const SizedBox(height: 8),
                  _Block(
                    width: MediaQuery.of(context).size.width * 0.4,
                    height: 12,
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

/// A column of feed-card skeletons, drop-in replacement for a
/// CircularProgressIndicator while a list loads.
class ShimmerFeedList extends StatelessWidget {
  final int count;
  const ShimmerFeedList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: List.generate(count, (_) => const ShimmerFeedCard()),
    );
  }
}

/// Skeleton for a simple list tile row (avatar + two lines), used for
/// chat/comments/audit/device-style lists.
class ShimmerTileList extends StatelessWidget {
  final int count;
  const ShimmerTileList({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: count,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const _Block(
                width: 40,
                height: 40,
                radius: BorderRadius.all(Radius.circular(20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Block(
                      width: MediaQuery.of(context).size.width * 0.5,
                      height: 12,
                    ),
                    const SizedBox(height: 6),
                    _Block(
                      width: MediaQuery.of(context).size.width * 0.3,
                      height: 10,
                    ),
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

/// Shimmer replacement for the small in-button / inline
/// `CircularProgressIndicator` -- a little rounded block that shimmers.
/// The app uses shimmer for every loading state, never a spinning circle.
/// Defaults to the surrounding text/icon colour so it reads correctly on
/// buttons as well as on plain backgrounds.
class ShimmerSpinner extends StatelessWidget {
  final double size;
  final Color? color;
  const ShimmerSpinner({super.key, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: Shimmer.fromColors(
        baseColor: c.withValues(alpha: 0.30),
        highlightColor: c.withValues(alpha: 0.95),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(size / 3),
          ),
        ),
      ),
    );
  }
}

/// A shimmering filled box -- the loading placeholder for a photo/video
/// thumbnail or any media area (replaces the old grey box + spinner).
class ShimmerFill extends StatelessWidget {
  const ShimmerFill({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(child: Container(color: Colors.white));
  }
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// Download progress readout: a thin bar plus "12.3 / 27.0 MB (45%)".
/// [received]/[total] in bytes; total <= 0 means unknown size (shows just
/// the amount so far with an indeterminate bar). Once everything has
/// arrived it switches to [doneLabel] while decryption/saving finishes.
class DownloadProgress extends StatelessWidget {
  final int received;
  final int total;
  final Color color;
  final String doneLabel;
  const DownloadProgress({
    super.key,
    required this.received,
    required this.total,
    this.color = Colors.white,
    this.doneLabel = 'প্রস্তুত হচ্ছে...',
  });

  @override
  Widget build(BuildContext context) {
    final known = total > 0;
    final done = known && received >= total;
    final fraction = known ? (received / total).clamp(0.0, 1.0) : null;
    final String label;
    if (done) {
      label = doneLabel;
    } else if (fraction != null) {
      label =
          'ডাউনলোড হচ্ছে  ${_mb(received)} / ${_mb(total)} MB  (${(fraction * 100).toStringAsFixed(0)}%)';
    } else {
      label = 'ডাউনলোড হচ্ছে  ${_mb(received)} MB';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: done ? null : fraction,
            minHeight: 5,
            color: color,
            backgroundColor: color.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
}
