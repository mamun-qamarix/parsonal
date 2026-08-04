import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';

class ReelItem {
  final VaultEntry entry;
  final bool isMatch;
  ReelItem({required this.entry, required this.isMatch});
}

class ReelService {
  final _dio = ApiClient.instance.dio;

  Future<List<ReelItem>> getFeed(Uint8List vmk, {bool favoritesOnly = false, String? categoryId}) async {
    final res = await _dio.get('/reel/feed', queryParameters: {
      'favorites_only': favoritesOnly,
      if (categoryId != null) 'category_id': categoryId,
    });
    final items = <ReelItem>[];
    for (final raw in (res.data as List)) {
      final entryJson = raw['entry'] as Map<String, dynamic>;
      final entry = VaultEntry.fromJson(entryJson);
      entry.decryptedText = entryJson['enc_payload'] != null ? await _safeDecrypt(vmk, entryJson['enc_payload']) : null;
      items.add(ReelItem(entry: entry, isMatch: raw['is_match'] == true));
    }
    return items;
  }

  Future<String> _safeDecrypt(Uint8List vmk, String enc) async {
    try {
      return await VaultCrypto.decryptText(vmk, enc);
    } catch (_) {
      return '[unable to decrypt]';
    }
  }
}
