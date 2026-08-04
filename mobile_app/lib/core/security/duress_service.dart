import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../storage/secure_storage_service.dart';

/// Duress/panic PIN check happens entirely on-device, with no network call,
/// so entering it under duress leaves no server-side trace. The real
/// server-side bcrypt hash (set via /auth/duress/set) is only a backup for
/// cross-device recovery, not the primary check path.
class DuressService {
  static Future<String> _localHash(String pin, String spouseId) async {
    final bytes = utf8.encode('$pin::$spouseId::couple-vault-duress');
    final digest = await Sha256().hash(bytes);
    return base64Encode(digest.bytes);
  }

  static Future<void> setLocalPin(String pin, String spouseId) async {
    final hash = await _localHash(pin, spouseId);
    await SecureStorageService.instance.setDuressPinHash(hash);
  }

  static Future<bool> matches(String enteredValue, String spouseId) async {
    final stored = await SecureStorageService.instance.duressPinHash;
    if (stored == null) return false;
    final candidate = await _localHash(enteredValue, spouseId);
    return candidate == stored;
  }
}
