import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../models/models.dart';

class ChatService {
  final _dio = ApiClient.instance.dio;

  Future<List<ChatMessageModel>> getHistory(
    Uint8List vmk, {
    String? before,
    int limit = 50,
  }) async {
    final res = await _dio.get(
      '/chat/messages',
      queryParameters: {if (before != null) 'before': before, 'limit': limit},
    );
    final messages = (res.data as List)
        .map((e) => ChatMessageModel.fromJson(e))
        .toList();
    for (final m in messages) {
      if (m.encPayload != null) {
        try {
          m.decryptedText = await VaultCrypto.decryptText(vmk, m.encPayload!);
        } catch (_) {
          m.decryptedText = '[ডিক্রিপ্ট করা যায়নি]';
        }
      }
    }
    return messages;
  }

  Future<void> sendTextViaWs(Uint8List vmk, String text, {String? replyToId}) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    WsClient.instance.send({
      'type': 'chat_message',
      'payload': {
        'content_type': 'text',
        'enc_payload': enc,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    });
  }

  Future<ChatMessageModel> sendMedia({
    required String contentType,
    required String mediaAssetId,
    String? caption,
    String? replyToId,
  }) async {
    final res = await _dio.post(
      '/chat/messages',
      data: {
        'content_type': contentType,
        'media_asset_id': mediaAssetId,
        if (caption != null) 'enc_payload': caption,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    );
    return ChatMessageModel.fromJson(res.data);
  }

  Future<void> markRead(String messageId) async {
    await _dio.post('/chat/messages/$messageId/read');
  }

  Future<List<ChatMediaItem>> listMedia() async {
    final res = await _dio.get('/chat/media');
    return (res.data as List).map((e) => ChatMediaItem.fromJson(e)).toList();
  }
}
