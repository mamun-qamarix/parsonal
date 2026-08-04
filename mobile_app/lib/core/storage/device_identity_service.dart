import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A stable per-installation identifier, generated once and kept in
/// SharedPreferences (NOT flutter_secure_storage) so it survives
/// SecureStorageService.clearAll() (logout, device-revoked-elsewhere) --
/// the whole point is that the same physical phone re-logging in still
/// looks like the same phone to the backend, so it reuses its existing
/// Device row instead of piling up duplicates. It naturally resets on an
/// actual app uninstall, same as any other local app data. See
/// DECISIONS.md #20.
class DeviceIdentityService {
  DeviceIdentityService._();
  static const _kDeviceUuid = 'device_installation_uuid';

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kDeviceUuid);
    if (existing != null) return existing;
    final generated = const Uuid().v4();
    await prefs.setString(_kDeviceUuid, generated);
    return generated;
  }
}
