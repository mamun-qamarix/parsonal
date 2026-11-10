import 'package:shared_preferences/shared_preferences.dart';

import '../storage/secure_storage_service.dart';

/// Where the backend lives. There's no setup code anymore (DECISIONS.md
/// #54), so the address comes from, in order:
///   1. what this phone already used before (kept in SharedPreferences,
///      deliberately outside secure storage so logout doesn't wipe it),
///   2. an older install's secure-storage session,
///   3. the build-time default: `flutter build apk --dart-define=SERVER_URL=https://vault.example.com`.
/// The login screen also lets you type it once if none of these exist.
class ServerConfig {
  static const _kPref = 'server_url_v2';
  static const buildDefault = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'https://parsonal.qamarix.com',
  );

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPref);
    if (saved != null && saved.isNotEmpty) return saved;
    final legacy = await SecureStorageService.instance.server;
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return buildDefault.isEmpty ? null : buildDefault;
  }

  static Future<void> set(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPref, u);
  }
}
