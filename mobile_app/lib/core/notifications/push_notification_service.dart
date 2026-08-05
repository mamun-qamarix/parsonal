import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../services/profile_service.dart';

/// Fires when a push arrives while the app is fully backgrounded/killed.
/// Must be a top-level (or static) function per the firebase_messaging
/// contract, since it can run in its own isolate.
///
/// There is intentionally nothing to do here: every push we send is a
/// plain FCM "notification" message (see backend/app/services/
/// notifications.py), which Android already shows in the system tray on
/// its own without any app code running. This handler only needs to exist
/// so FCM has something registered to wake for.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Registers this device's FCM token with the backend so it knows where to
/// send generic, content-free push wake-ups (see project.md §7 and
/// DECISIONS.md). Foreground realtime updates already go over the
/// WebSocket (ws_client.dart) -- FCM's only job is covering the
/// background/killed-app case, so there is deliberately no foreground
/// message handler here beyond keeping the token fresh.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _initialized = false;

  /// Call once, early in app startup (regardless of auth state) -- just
  /// wires up the background handler and token-refresh listener. Safe to
  /// call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _sendToken(token);
      });
    } catch (e) {
      // Push notifications are a nice-to-have wake-up mechanism, never
      // something worth crashing startup over (e.g. if Firebase wasn't
      // configured for this build at all).
      debugPrint('Push notification init skipped: $e');
    }
  }

  /// Call once the user is actually authenticated (fresh login, biometric
  /// unlock, or a freshly-completed device pairing) -- requests the OS
  /// notification permission if needed and registers the current token.
  Future<void> registerToken() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _sendToken(token);
    } catch (e) {
      debugPrint('Push token registration skipped: $e');
    }
  }

  Future<void> _sendToken(String token) async {
    try {
      await ProfileService().updatePushToken(token);
    } catch (e) {
      debugPrint('Push token update failed: $e');
    }
  }
}
