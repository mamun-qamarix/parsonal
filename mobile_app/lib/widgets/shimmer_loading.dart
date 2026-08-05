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
