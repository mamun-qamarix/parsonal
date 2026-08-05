import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';

class ProfileService {
  final _dio = ApiClient.instance.dio;

  Future<ProfileModel> get(Uint8List vmk, String role) async {
    final res = await _dio.get('/profile/$role');
    final profile = ProfileModel.fromJson(res.data);
    if (profile.encDisplayName != null) {
      try {
        profile.decryptedName = await VaultCrypto.decryptText(
          vmk,
          profile.encDisplayName!,
        );
      } catch (_) {}
    }
    if (profile.encBio != null) {
      try {
        profile.decryptedBio = await VaultCrypto.decryptText(
          vmk,
          profile.encBio!,
        );
      } catch (_) {}
    }
    return profile;
  }

  Future<void> updateMine(
    Uint8List vmk, {
    String? name,
    String? bio,
    String? photoAssetId,
  }) async {
    final data = <String, dynamic>{};
    if (name != null)
      data['enc_display_name'] = await VaultCrypto.encryptText(vmk, name);
    if (bio != null) data['enc_bio'] = await VaultCrypto.encryptText(vmk, bio);
    if (photoAssetId != null) data['profile_photo_asset_id'] = photoAssetId;
    await _dio.put('/profile/me', data: data);
  }

  Future<Map<String, dynamic>?> getCountdown() async {
    final res = await _dio.get('/countdown');
    return res.data as Map<String, dynamic>?;
  }

  Future<void> setCountdown(DateTime target, {String? note}) async {
    await _dio.put(
      '/countdown',
      data: {'target_datetime': target.toUtc().toIso8601String()},
    );
  }

  Future<String> getSetting(String key, {String fallback = ''}) async {
    final res = await _dio.get('/settings/$key');
    return res.data['value'] as String? ?? fallback;
  }

  Future<void> setSetting(String key, String value) async {
    await _dio.put('/settings/$key', data: {'value': value});
  }

  Future<void> updatePushToken(String token) async {
    await _dio.put('/device/push-token', data: {'push_token': token});
  }
}
