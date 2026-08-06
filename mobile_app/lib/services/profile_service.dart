import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../core/network/connectivity_status.dart';
import '../core/storage/local_cache.dart';
import '../models/models.dart';

class ProfileService {
  final _dio = ApiClient.instance.dio;

  Future<ProfileModel> get(Uint8List vmk, String role) async {
    final cacheKey = 'profile_$role';
    dynamic data;
    try {
      final res = await _dio.get('/profile/$role');
      data = res.data;
      ConnectivityStatus.instance.offline.value = false;
      unawaited(LocalCache.instance.putJson(cacheKey, data));
    } on DioException {
      final cached = await LocalCache.instance.getJson(cacheKey);
      if (cached == null) rethrow;
      data = cached;
      ConnectivityStatus.instance.offline.value = true;
    }
    final profile = ProfileModel.fromJson(data);
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

  /// Either spouse can edit either profile -- same shared-trust model as
  /// everywhere else in the app. See DECISIONS.md.
  Future<void> updateRole(
    Uint8List vmk,
    String role, {
    String? name,
    String? bio,
    String? photoAssetId,
  }) async {
    final data = <String, dynamic>{};
    if (name != null)
      data['enc_display_name'] = await VaultCrypto.encryptText(vmk, name);
    if (bio != null) data['enc_bio'] = await VaultCrypto.encryptText(vmk, bio);
    if (photoAssetId != null) data['profile_photo_asset_id'] = photoAssetId;
    await _dio.put('/profile/$role', data: data);
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
