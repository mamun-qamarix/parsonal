import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';

class WishlistService {
  final _dio = ApiClient.instance.dio;

  Future<List<WishlistItemModel>> list(
    Uint8List vmk, {
    String? ownerRole,
  }) async {
    final res = await _dio.get(
      '/wishlist',
      queryParameters: {if (ownerRole != null) 'owner_role': ownerRole},
    );
    final items = (res.data as List)
        .map((e) => WishlistItemModel.fromJson(e))
        .toList();
    for (final i in items) {
      try {
        i.decryptedText = await VaultCrypto.decryptText(vmk, i.encPayload);
      } catch (_) {
        i.decryptedText = '[unable to decrypt]';
      }
    }
    return items;
  }

  Future<WishlistItemModel> create(
    Uint8List vmk,
    String text, {
    String? categoryId,
  }) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    final res = await _dio.post(
      '/wishlist',
      data: {'enc_payload': enc, 'category_id': categoryId},
    );
    final item = WishlistItemModel.fromJson(res.data);
    item.decryptedText = text;
    return item;
  }

  Future<void> toggleFulfilled(String id, bool fulfilled) async {
    await _dio.patch('/wishlist/$id', data: {'is_fulfilled': fulfilled});
  }

  Future<void> delete(String id) async {
    await _dio.delete('/wishlist/$id');
  }
}
