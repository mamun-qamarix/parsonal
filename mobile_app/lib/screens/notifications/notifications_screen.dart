import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/notification_service.dart';
import '../../widgets/shimmer_loading.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// The in-app notification inbox -- every notify_spouse() event that's
/// happened, persisted server-side (previously these were purely
/// ephemeral: a WebSocket ping shown as a SnackBar if you happened to be
/// looking at the right moment, with no history at all). Opening this
/// screen marks everything read. See DECISIONS.md.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  List<NotificationModel> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    // Opening the inbox counts as having seen everything in it.
    unawaited(_service.markAllRead());
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'content_new':
      case 'content_edited':
      case 'content_deleted':
        return Iconsax.gallery;
      case 'reaction':
        return Iconsax.emoji_happy;
      case 'comment':
        return Iconsax.message_2;
      case 'consent_request':
      case 'consent_resolved':
        return Iconsax.sms_notification;
      case 'phrase':
        return Iconsax.heart_copy;
      case 'chat':
        return Iconsax.message_text_1;
      default:
        return Iconsax.notification;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('নোটিফিকেশন')),
      body: _loading
          ? const ShimmerTileList()
          : _items.isEmpty
          ? const Center(
              child: Text('এখনো কোনো নোটিফিকেশন নেই', style: TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = _items[i];
                final wasUnread = n.readAt == null;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: wasUnread
                        ? AppColors.halalGreen.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.1),
                    child: Icon(
                      _iconFor(n.category),
                      color: wasUnread ? AppColors.halalGreen : Colors.grey,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    n.body,
                    style: TextStyle(
                      fontWeight: wasUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    DateFormat.yMMMd().add_jm().format(n.createdAt.toLocal()),
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
    );
  }
}
