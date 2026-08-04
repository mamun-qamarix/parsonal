import 'dart:typed_data';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../models/models.dart';

class ChatService {
  final _dio = ApiClient.instance.dio;

  Future<List<ChatMessageModel>> getHistory(Uint8List vmk, {String? before}) async {
    final res = await _dio.get('/chat/messages', queryParameters: {if (before != null) 'before': before});
    final messages = (res.data as List).map((e) => ChatMessageModel.fromJson(e)).toList();
    for (final m in messages) {
      if (m.encPayload != null) {
        try {
          m.decryptedText = await VaultCrypto.decryptText(vmk, m.encPayload!);
        } catch (_) {
          m.decryptedText = '[unable to decrypt]';
        }
      }
    }
    return messages;
  }

  Future<void> sendTextViaWs(Uint8List vmk, String text) async {
    final enc = await VaultCrypto.encryptText(vmk, text);
    WsClient.instance.send({
      'type': 'chat_message',
      'payload': {'content_type': 'text', 'enc_payload': enc},
    });
  }

  Future<ChatMessageModel> sendMedia({required String contentType, required String mediaAssetId, String? caption}) async {
    final res = await _dio.post('/chat/messages', data: {
      'content_type': contentType,
      'media_asset_id': mediaAssetId,
      if (caption != null) 'enc_payload': caption,
    });
    return ChatMessageModel.fromJson(res.data);
  }

  Future<void> markRead(String messageId) async {
    await _dio.post('/chat/messages/$messageId/read');
  }
}
