import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final vmk = context.read<SessionProvider>().vmk;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
    );
  }
}
