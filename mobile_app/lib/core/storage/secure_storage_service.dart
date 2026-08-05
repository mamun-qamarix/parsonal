import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything that must never leave this device unencrypted lives here,
/// backed by Android Keystore / iOS Keychain via flutter_secure_storage.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kServer = 'server_url';
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kVmk = 'vault_master_key';
  static const _kRole = 'role';
  static const _kSpouseId = 'spouse_id';
  static const _kDeviceId = 'device_id';
  static const _kDuressPin = 'duress_pin_local_hash';
  static const _kFaceEnrolled = 'face_enrolled';
  static const _kLastPasswordAuthAt = 'last_password_auth_at';

  Future<void> saveSession({
    required String server,
    required String accessToken,
    required String refreshToken,
    required String vmkB64,
    required String role,
    required String spouseId,
    String? deviceId,
  }) async {
    await Future.wait([
      _storage.write(key: _kServer, value: server),
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(key: _kVmk, value: vmkB64),
      _storage.write(key: _kRole, value: role),
      _storage.write(key: _kSpouseId, value: spouseId),
      if (deviceId != null) _storage.write(key: _kDeviceId, value: deviceId),
    ]);
  }

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _kAccessToken, value: token);

  Future<String?> get server => _storage.read(key: _kServer);
  Future<String?> get accessToken => _storage.read(key: _kAccessToken);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshToken);
  Future<String?> get vmkB64 => _storage.read(key: _kVmk);
  Future<String?> get role => _storage.read(key: _kRole);
  Future<String?> get spouseId => _storage.read(key: _kSpouseId);
  Future<String?> get deviceId => _storage.read(key: _kDeviceId);

  Future<void> setFaceEnrolled(bool value) =>
      _storage.write(key: _kFaceEnrolled, value: value.toString());
  Future<bool> get faceEnrolled async =>
      (await _storage.read(key: _kFaceEnrolled)) == 'true';

  Future<void> setDuressPinHash(String hash) =>
      _storage.write(key: _kDuressPin, value: hash);
  Future<String?> get duressPinHash => _storage.read(key: _kDuressPin);

  /// Timestamp of the last successful PASSWORD login (not biometric
  /// unlock) -- drives the "password once an hour, biometric in between"
  /// policy. See DECISIONS.md #27.
  Future<void> setLastPasswordAuthAt(DateTime value) =>
      _storage.write(key: _kLastPasswordAuthAt, value: value.toIso8601String());
  Future<DateTime?> get lastPasswordAuthAt async {
    final raw = await _storage.read(key: _kLastPasswordAuthAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<bool> get hasSession async =>
      (await accessToken) != null && (await vmkB64) != null;

  Future<void> clearAll() => _storage.deleteAll();
}
