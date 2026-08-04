import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

void showMatchCelebration(BuildContext context) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _MatchCelebration(onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _MatchCelebration extends StatefulWidget {
  final VoidCallback onDone;
  const _MatchCelebration({required this.onDone});

  @override
  State<_MatchCelebration> createState() => _MatchCelebrationState();
}

class _MatchCelebrationState extends State<_MatchCelebration> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            children: [
              for (var i = 0; i < 14; i++)
                _floatingHeart(context, i, t),
              Center(
                child: Opacity(
                  opacity: (t < 0.15 ? t / 0.15 : (t > 0.7 ? (1 - (t - 0.7) / 0.3) : 1.0)).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.8 + (t < 0.3 ? t / 0.3 * 0.3 : 0.3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('💚', style: TextStyle(fontSize: 40)),
                          SizedBox(height: 6),
                          Text('It\'s a match!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                          Text('You both loved this', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _floatingHeart(BuildContext context, int seedIndex, double t) {
    final rand = Random(seedIndex * 97);
    final size = MediaQuery.of(context).size;
    final startX = rand.nextDouble() * size.width;
    final delay = rand.nextDouble() * 0.4;
    final localT = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    final y = size.height * (1 - localT) * 0.9 + size.height * 0.1;
    final opacity = localT < 0.1 ? localT / 0.1 : (localT > 0.8 ? (1 - localT) / 0.2 : 1.0);
    return Positioned(
      left: startX,
      top: y,
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Text(['❤️', '💚', '💕'][seedIndex % 3], style: TextStyle(fontSize: 20 + rand.nextInt(16).toDouble(), color: AppColors.halalGreen)),
      ),
    );
  }
}
