import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/session_provider.dart';

/// Wraps the whole app to:
/// - block screenshots / screen recording app-wide. On Android this is
///   FLAG_SECURE, set natively in MainActivity.kt's onCreate — that also
///   blocks the real content from ever reaching the recent-apps thumbnail,
///   since that thumbnail *is* a screenshot taken by the OS compositor.
///   iOS has no equivalent screenshot-blocking API, so the blur overlay
///   below is what covers content there.
/// - show a blur/cover overlay when backgrounded (all platforms).
/// - lock the session (force re-auth) whenever the app is backgrounded.
/// - track user interaction to drive the auto-lock inactivity timer.
class AppLockGuard extends StatefulWidget {
  final Widget child;
  const AppLockGuard({super.key, required this.child});

  @override
  State<AppLockGuard> createState() => _AppLockGuardState();
}

class _AppLockGuardState extends State<AppLockGuard> with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = context.read<SessionProvider>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      setState(() => _obscured = true);
      if (state == AppLifecycleState.paused) {
        session.lock();
      }
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _obscured = false);
      session.registerActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => context.read<SessionProvider>().registerActivity(),
      child: Stack(
        children: [
          widget.child,
          if (_obscured)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: const Center(
                  child: Icon(Icons.lock_outline, size: 48, color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
