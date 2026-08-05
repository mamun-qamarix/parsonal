import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
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
    final res = await _dio.get(
      '/categories',
      queryParameters: {'scope': scope},
    );
    final cats = (res.data as List).map((e) => Category.fromJson(e)).toList();
    for (final c in cats) {
      c.decryptedName = await VaultCrypto.decryptText(vmk, c.encName);
    }
    return cats;
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
    final res = await _dio.get(
      '/vault/entries',
      queryParameters: {
        if (authorRole != null) 'author_role': authorRole,
        if (contentType != null) 'content_type': contentType,
        if (categoryId != null) 'category_id': categoryId,
        'favorites_only': favoritesOnly,
      },
    );
    final entries = (res.data as List)
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
      return '[unable to decrypt]';
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
