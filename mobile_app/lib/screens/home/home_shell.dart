import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/connectivity_status.dart';
import '../../core/network/ws_client.dart';
import '../../providers/session_provider.dart';
import '../../services/profile_cache.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../reel/reel_screen.dart';
import 'home_tab.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription? _wsSub;

  static const _pages = [
    HomeTab(),
    ReelScreen(),
    ChatScreen(),
    ProfileScreen(),
  ];

  static const _labels = {
    'content_new': 'সঙ্গী নতুন কিছু যোগ করেছে 💚',
    'content_edited': 'ভল্টের একটা এন্ট্রি এডিট হয়েছে',
    'content_deleted': 'ভল্টের একটা এন্ট্রি মুছে ফেলা হয়েছে',
    'reaction': 'সঙ্গী কিছুতে রিয়্যাক্ট করেছে',
    'comment': 'সঙ্গীর নতুন একটা মন্তব্য এসেছে',
    'phrase': 'সঙ্গী নতুন একটা প্রিয় লাইন যোগ করেছে',
  };

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>();
    // Reopen on whichever tab was last open (see SessionProvider.
    // lastTabIndex) instead of always defaulting to home -- most visible
    // right after a lock/unlock cycle rebuilds this whole widget fresh.
    _index = session.lastTabIndex;
    final vmk = session.vmk;
    if (vmk != null) ProfileCache.instance.warmUp(vmk);
    _wsSub = WsClient.instance.events.listen((data) {
      final type = data['type'];
      if (type == 'daily_reminder') {
        _showBanner(
          data['message'] as String? ?? "তোমার জন্য কিছু অপেক্ষা করছে 💚",
        );
      } else if (_labels.containsKey(type)) {
        _showBanner(_labels[type]!);
      }
    });
  }

  void _showBanner(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  void _selectTab(int i) {
    setState(() => _index = i);
    context.read<SessionProvider>().lastTabIndex = i;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // On any tab other than home, back goes to the home tab first
      // instead of exiting the app straight away -- only actually pops
      // (exits) once already on home. See DECISIONS.md.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _selectTab(0);
      },
      child: Scaffold(
        body: Column(
          children: [
            const _OfflineBanner(),
            Expanded(child: IndexedStack(index: _index, children: _pages)),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: const [
          NavigationDestination(
            icon: Icon(Iconsax.home),
            selectedIcon: Icon(Iconsax.home_copy),
            label: 'হোম',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.play_circle),
            selectedIcon: Icon(Iconsax.play_circle),
            label: 'রিল',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.message_2),
            selectedIcon: Icon(Iconsax.message_2_copy),
            label: 'চ্যাট',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.profile_circle),
            selectedIcon: Icon(Iconsax.profile_circle_copy),
            label: 'প্রোফাইল',
          ),
          ],
        ),
      ),
    );
  }
}

/// A thin strip that appears whenever a read-path service has just fallen
/// back to [LocalCache] because the network call failed -- so the user
/// knows they may be looking at slightly stale, previously-saved data
/// rather than a live feed. One instance here in the shell covers every
/// tab (including chat, which lives inside this same IndexedStack).
/// Clears itself automatically the moment any service call succeeds
/// against the live network again. See DECISIONS.md.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityStatus.instance.offline,
      builder: (context, offline, _) {
        if (!offline) return const SizedBox.shrink();
        return SafeArea(
          bottom: false,
          child: Container(
            width: double.infinity,
            color: Colors.orange.shade800,
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: const Text(
              'অফলাইন — সংরক্ষিত তথ্য দেখানো হচ্ছে',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}
