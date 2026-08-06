import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../core/network/connectivity_status.dart';
import '../core/storage/local_cache.dart';
import '../models/models.dart';

class VaultService {
  final _dio = ApiClient.instance.dio;

  Future<Category> createCategory(
    Uint8List vmk,
    String scope,
    String name,
  ) async {
    final enc = await VaultCrypto.encryptText(vmk, name);
    final res = await _dio.post(
      '/categories',
      data: {'scope': scope, 'enc_payload': enc},
    );
    final cat = Category.fromJson(res.data);
    cat.decryptedName = name;
    return cat;
  }

  Future<List<Category>> listCategories(Uint8List vmk, String scope) async {
    final cacheKey = 'categories_$scope';
    final raw = await _getWithOfflineFallback(
      cacheKey,
      () => _dio.get('/categories', queryParameters: {'scope': scope}),
    );
    final cats = (raw as List).map((e) => Category.fromJson(e)).toList();
    for (final c in cats) {
      c.decryptedName = await VaultCrypto.decryptText(vmk, c.encName);
    }
    return cats;
  }

  /// Runs [request], caching the raw (still-encrypted-where-applicable)
  /// response under [cacheKey] on success. On a network failure, falls
  /// back to whatever was last cached for [cacheKey] so read screens keep
  /// working offline -- if nothing's cached yet, the original error is
  /// rethrown as before. See DECISIONS.md and [LocalCache].
  Future<dynamic> _getWithOfflineFallback(
    String cacheKey,
    Future<Response> Function() request,
  ) async {
    try {
      final res = await request();
      ConnectivityStatus.instance.offline.value = false;
      unawaited(LocalCache.instance.putJson(cacheKey, res.data));
      return res.data;
    } on DioException {
      final cached = await LocalCache.instance.getJson(cacheKey);
      if (cached == null) rethrow;
      ConnectivityStatus.instance.offline.value = true;
      return cached;
    }
  }

  Future<VaultEntry> createEntry(
    Uint8List vmk, {
    required String contentType,
    required String text,
    String? categoryId,
    List<String> mediaAssetIds = const [],
  }) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    final res = await _dio.post(
      '/vault/entries',
      data: {
        'content_type': contentType,
        'category_id': categoryId,
        'enc_payload': enc,
        'media_asset_ids': mediaAssetIds,
      },
    );
    final entry = VaultEntry.fromJson(res.data);
    entry.decryptedText = text;
    return entry;
  }

  Future<List<VaultEntry>> listEntries(
    Uint8List vmk, {
    String? authorRole,
    String? contentType,
    String? categoryId,
    bool favoritesOnly = false,
  }) async {
    final cacheKey =
        'vault_entries_${authorRole ?? '_'}_${contentType ?? '_'}_${categoryId ?? '_'}_$favoritesOnly';
    final raw = await _getWithOfflineFallback(
      cacheKey,
      () => _dio.get(
        '/vault/entries',
        queryParameters: {
          if (authorRole != null) 'author_role': authorRole,
          if (contentType != null) 'content_type': contentType,
          if (categoryId != null) 'category_id': categoryId,
          'favorites_only': favoritesOnly,
        },
      ),
    );
    final entries = (raw as List)
        .map((e) => VaultEntry.fromJson(e))
        .toList();
    for (final entry in entries) {
      entry.decryptedText = await _safeDecrypt(vmk, entry.encPayload);
    }
    return entries;
  }

  Future<String> _safeDecrypt(Uint8List vmk, String enc) async {
    try {
      return await VaultCrypto.decryptText(vmk, enc);
    } catch (_) {
      return '[ডিক্রিপ্ট করা যায়নি]';
    }
  }

  Future<VaultEntry> getEntry(Uint8List vmk, String id) async {
    final res = await _dio.get('/vault/entries/$id');
    final entry = VaultEntry.fromJson(res.data);
    entry.decryptedText = await _safeDecrypt(vmk, entry.encPayload);
    return entry;
  }

  Future<bool> toggleFavorite(String entryId) async {
    final res = await _dio.post('/vault/entries/$entryId/favorite');
    return res.data['is_favorite'] as bool;
  }

  /// Edits an entry's text/category immediately -- no spouse approval.
  /// See DECISIONS.md.
  Future<VaultEntry> updateEntry(
    Uint8List vmk,
    String entryId,
    String text, {
    String? categoryId,
  }) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    final res = await _dio.put(
      '/vault/entries/$entryId',
      data: {'enc_payload': enc, if (categoryId != null) 'category_id': categoryId},
    );
    final entry = VaultEntry.fromJson(res.data);
    entry.decryptedText = text;
    return entry;
  }

  /// Deletes an entry immediately -- no spouse approval. See DECISIONS.md.
  Future<void> deleteEntry(String entryId) async {
    await _dio.delete('/vault/entries/$entryId');
  }

  Future<ConsentRequestModel> requestEdit(
    Uint8List vmk,
    String entryId,
    String newText,
  ) async {
    final enc = await VaultCrypto.encryptText(vmk, newText);
    final res = await _dio.post(
      '/vault/entries/$entryId/edit-request',
      data: {'enc_payload': enc},
    );
    return ConsentRequestModel.fromJson(res.data);
  }

  Future<ConsentRequestModel> requestDelete(String entryId) async {
    final res = await _dio.post('/vault/entries/$entryId/delete-request');
    return ConsentRequestModel.fromJson(res.data);
  }

  Future<List<ConsentRequestModel>> listConsentRequests({
    String status = 'pending',
  }) async {
    final res = await _dio.get(
      '/vault/consent-requests',
      queryParameters: {'status': status},
    );
    return (res.data as List)
        .map((e) => ConsentRequestModel.fromJson(e))
        .toList();
  }

  Future<void> decideConsentRequest(String requestId, bool approve) async {
    await _dio.post(
      '/vault/consent-requests/$requestId/decide',
      data: {'approve': approve},
    );
  }
}
