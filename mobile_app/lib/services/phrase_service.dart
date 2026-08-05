import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';

class PhraseService {
  final _dio = ApiClient.instance.dio;

  Future<List<PhraseModel>> list(
    Uint8List vmk, {
    String? direction,
    bool sortByRating = false,
  }) async {
    final res = await _dio.get(
      '/phrases',
      queryParameters: {
        if (direction != null) 'direction': direction,
        'sort_by_rating': sortByRating,
      },
    );
    final phrases = (res.data as List)
        .map((e) => PhraseModel.fromJson(e))
        .toList();
    for (final p in phrases) {
      try {
        p.decryptedText = await VaultCrypto.decryptText(vmk, p.encPayload);
      } catch (_) {
        p.decryptedText = '[ডিক্রিপ্ট করা যায়নি]';
      }
    }
    return phrases;
  }

  Future<PhraseModel> create(
    Uint8List vmk,
    String direction,
    String text,
  ) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    final res = await _dio.post(
      '/phrases',
      data: {'direction': direction, 'enc_payload': enc},
    );
    final phrase = PhraseModel.fromJson(res.data);
    phrase.decryptedText = text;
    return phrase;
  }

  Future<void> rate(String id, int rating) async {
    await _dio.post('/phrases/$id/rate', data: {'rating': rating});
  }

  Future<PhraseModel> update(Uint8List vmk, String id, String text) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    final res = await _dio.put('/phrases/$id', data: {'enc_payload': enc});
    final phrase = PhraseModel.fromJson(res.data);
    phrase.decryptedText = text;
    return phrase;
  }

  Future<void> delete(String id) async {
    await _dio.delete('/phrases/$id');
  }
}
