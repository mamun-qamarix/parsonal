import 'dart:async';

import 'package:flutter/material.dart';

import '../core/network/ws_client.dart';
import '../screens/notifications/notifications_screen.dart';
import '../services/notification_service.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Bell icon with an unread-count badge -- fetches the count on mount and
/// refreshes it whenever a relevant WebSocket event arrives (so the badge
/// updates live while the app is open, not just on next launch). Tapping
/// opens the notification inbox and marks everything read. See
/// DECISIONS.md.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _service = NotificationService();
  int _unread = 0;
  StreamSubscription? _wsSub;

  static const _watchedTypes = {
    'content_new', 'content_edited', 'content_deleted', 'reaction',
    'comment', 'consent_request', 'consent_resolved', 'phrase', 'chat',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
    _wsSub = WsClient.instance.events.listen((data) {
      if (_watchedTypes.contains(data['type'])) _refresh();
    });
  }

  Future<void> _refresh() async {
    try {
      final count = await _service.unreadCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {}
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _refresh();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Iconsax.notification),
          tooltip: 'নোটিফিকেশন',
          onPressed: _open,
        ),
        if (_unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                _unread > 99 ? '99+' : '$_unread',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
