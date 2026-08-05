import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/ws_client.dart';
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
    'content_new': 'Your spouse added something new 💚',
    'reaction': 'Your spouse reacted to something',
    'comment': 'New comment from your spouse',
    'consent_request': 'A request needs your approval',
    'consent_resolved': 'Your request was answered',
    'phrase': 'Your spouse added a new line',
  };

  @override
  void initState() {
    super.initState();
    _wsSub = WsClient.instance.events.listen((data) {
      final type = data['type'];
      if (type == 'daily_reminder') {
        _showBanner(
          data['message'] as String? ?? "You have something waiting for you 💚",
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
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.play_circle),
            selectedIcon: Icon(Iconsax.play_circle),
            label: 'Reel',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.message_2),
            selectedIcon: Icon(Iconsax.message_2_copy),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Iconsax.profile_circle),
            selectedIcon: Icon(Iconsax.profile_circle_copy),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
