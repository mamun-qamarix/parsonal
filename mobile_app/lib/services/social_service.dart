import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';

const kHeartEmoji = '❤️';

class SocialService {
  final _dio = ApiClient.instance.dio;

  Future<bool> addReaction(
    String targetType,
    String targetId,
    String emoji,
  ) async {
    final res = await _dio.post(
      '/reactions',
      data: {'target_type': targetType, 'target_id': targetId, 'emoji': emoji},
    );
    return res.data['match_formed'] == true;
  }

  Future<void> removeReaction(
    String targetType,
    String targetId,
    String emoji,
  ) async {
    await _dio.delete(
      '/reactions',
      data: {'target_type': targetType, 'target_id': targetId, 'emoji': emoji},
    );
  }

  Future<List<ReactionPersonGroup>> getReactionBreakdown(
    String targetType,
    String targetId,
  ) async {
    final res = await _dio.get('/reactions/$targetType/$targetId');
    return (res.data as List)
        .map((e) => ReactionPersonGroup.fromJson(e))
        .toList();
  }

  Future<bool> checkMatchCelebration(String targetType, String targetId) async {
    final res = await _dio.get(
      '/reactions/$targetType/$targetId/match-celebration',
    );
    return res.data['show_celebration'] as bool;
  }

  Future<CommentModel> addComment(
    Uint8List vmk,
    String targetType,
    String targetId,
    String text,
  ) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    final res = await _dio.post(
      '/comments',
      data: {
        'target_type': targetType,
        'target_id': targetId,
        'enc_payload': enc,
      },
    );
    final comment = CommentModel.fromJson(res.data);
    comment.decryptedText = text;
    return comment;
  }

  Future<List<CommentModel>> listComments(
    Uint8List vmk,
    String targetType,
    String targetId,
  ) async {
    final res = await _dio.get('/comments/$targetType/$targetId');
    final comments = (res.data as List)
        .map((e) => CommentModel.fromJson(e))
        .toList();
    for (final c in comments) {
      try {
        c.decryptedText = await VaultCrypto.decryptText(vmk, c.encPayload);
      } catch (_) {
        c.decryptedText = '[ডিক্রিপ্ট করা যায়নি]';
      }
    }
    return comments;
  }

  Future<CommentModel> updateComment(
    Uint8List vmk,
    String commentId,
    String text,
  ) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    final res = await _dio.put('/comments/$commentId', data: {'enc_payload': enc});
    final comment = CommentModel.fromJson(res.data);
    comment.decryptedText = text;
    return comment;
  }

  Future<void> deleteComment(String commentId) async {
    await _dio.delete('/comments/$commentId');
  }

  Future<bool> toggleFavoriteGeneric(String targetType, String targetId) async {
    final res = await _dio.post(
      '/favorites/toggle',
      data: {'target_type': targetType, 'target_id': targetId},
    );
    return res.data['is_favorite'] as bool;
  }
}
