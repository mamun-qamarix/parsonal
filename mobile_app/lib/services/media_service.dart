import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';

// Big media (up to 1GB, see DECISIONS.md) can take a long time on a slow
// mobile connection -- the app-wide default timeouts (tuned for quick API
// calls) would abort a transfer that's still healthily in progress.
final _transferOptions = Options(sendTimeout: const Duration(minutes: 30), receiveTimeout: const Duration(minutes: 30));

class MediaService {
  final _dio = ApiClient.instance.dio;

  /// Encrypts [bytes] (and optional [thumbnailBytes]) client-side before
  /// upload. The server only ever stores ciphertext — see DECISIONS.md §1.
  /// [onSendProgress] reports (bytesSent, totalBytes) as the encrypted
  /// upload streams to the server, for a progress bar on large files.
  Future<MediaAsset> upload(
    Uint8List vmk, {
    required String kind, // image | video | voice | file
    required Uint8List bytes,
    Uint8List? thumbnailBytes,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final encMain = await VaultCrypto.encryptBytes(vmk, bytes);
    final encThumb = thumbnailBytes != null ? await VaultCrypto.encryptBytes(vmk, thumbnailBytes) : null;

    final form = FormData.fromMap({
      'kind': kind,
      'file': MultipartFile.fromBytes(encMain, filename: 'blob.enc'),
      if (encThumb != null) 'thumbnail': MultipartFile.fromBytes(encThumb, filename: 'thumb.enc'),
    });
    final res = await _dio.post('/media/upload', data: form, options: _transferOptions, onSendProgress: onSendProgress);
    return MediaAsset.fromJson(res.data);
  }

  Future<Uint8List> downloadRaw(Uint8List vmk, String assetId) async {
    final res = await _dio.get<List<int>>('/media/$assetId/raw', options: _transferOptions.copyWith(responseType: ResponseType.bytes));
    final encBytes = Uint8List.fromList(res.data!);
    return VaultCrypto.decryptBytes(vmk, encBytes);
  }

  Future<Uint8List> downloadThumbnail(Uint8List vmk, String assetId) async {
    final res = await _dio.get<List<int>>('/media/$assetId/thumbnail', options: Options(responseType: ResponseType.bytes));
    final encBytes = Uint8List.fromList(res.data!);
    return VaultCrypto.decryptBytes(vmk, encBytes);
  }
}
