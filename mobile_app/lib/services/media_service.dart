import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/crypto/chunked_crypto.dart';
import '../core/crypto/vault_crypto.dart';
import '../core/network/api_client.dart';
import '../core/network/connectivity_status.dart';
import '../core/storage/local_cache.dart';
import '../models/models.dart';

// Big media (up to 1GB, see DECISIONS.md) can take a long time on a slow
// mobile connection -- the app-wide default timeouts (tuned for quick API
// calls) would abort a transfer that's still healthily in progress.
final _transferOptions = Options(
  sendTimeout: const Duration(minutes: 30),
  receiveTimeout: const Duration(minutes: 30),
);

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
    // Videos use the chunked (streamable) format so they can start playing
    // before the whole file has downloaded. See DECISIONS.md.
    final chunked = kind == 'video';
    final encMain = chunked
        ? await Isolate.run(() => ChunkedCrypto.encrypt(vmk, bytes))
        : await VaultCrypto.encryptBytes(vmk, bytes);
    final encThumb = thumbnailBytes != null
        ? await VaultCrypto.encryptBytes(vmk, thumbnailBytes)
        : null;

    final form = FormData.fromMap({
      'kind': kind,
      'chunked': chunked ? 'true' : 'false',
      'file': MultipartFile.fromBytes(encMain, filename: 'blob.enc'),
      if (encThumb != null)
        'thumbnail': MultipartFile.fromBytes(encThumb, filename: 'thumb.enc'),
    });
    final res = await _dio.post(
      '/media/upload',
      data: form,
      options: _transferOptions,
      onSendProgress: onSendProgress,
    );
    return MediaAsset.fromJson(res.data);
  }

  /// Backfills a thumbnail onto an already-uploaded video asset that
  /// doesn't have one yet. See DECISIONS.md.
  Future<void> attachThumbnail(
    Uint8List vmk,
    String assetId,
    Uint8List thumbnailBytes,
  ) async {
    final encThumb = await VaultCrypto.encryptBytes(vmk, thumbnailBytes);
    final form = FormData.fromMap({
      'thumbnail': MultipartFile.fromBytes(encThumb, filename: 'thumb.enc'),
    });
    await _dio.put('/media/$assetId/thumbnail', data: form);
  }

  /// Media assets are immutable once uploaded (looked up by id; a video's
  /// backfilled thumbnail is only requested once the server says it has
  /// one), so both download methods are CACHE-FIRST: previously-seen
  /// media is read from the on-disk cache of still-ENCRYPTED bytes (same
  /// ciphertext the server holds -- see [LocalCache]) instead of waiting on
  /// the network again, then decrypted locally as always. On a miss the
  /// network is used and the ciphertext is cached for next time. See
  /// DECISIONS.md.
  ///
  /// [onProgress] reports (bytesReceived, totalBytes) while a network
  /// download is in progress (total is -1 if the server didn't say). Not
  /// called at all on a cache hit, which is near-instant anyway.
  Future<Uint8List> downloadRaw(
    Uint8List vmk,
    String assetId, {
    void Function(int received, int total)? onProgress,
  }) => _download(vmk, assetId, 'raw', onProgress: onProgress);

  Future<Uint8List> downloadThumbnail(Uint8List vmk, String assetId) =>
      _download(vmk, assetId, 'thumb');

  Future<Uint8List> _download(
    Uint8List vmk,
    String assetId,
    String variant, {
    void Function(int received, int total)? onProgress,
  }) async {
    final cached = await LocalCache.instance.getBlob(assetId, variant);
    if (cached != null) {
      try {
        return await VaultCrypto.decryptBytes(vmk, cached);
      } catch (_) {
        // Corrupt/partial cache file -- fall through and refetch.
      }
    }
    final isRaw = variant == 'raw';
    final res = await _dio.get<List<int>>(
      isRaw ? '/media/$assetId/raw' : '/media/$assetId/thumbnail',
      options: isRaw
          ? _transferOptions.copyWith(responseType: ResponseType.bytes)
          : Options(responseType: ResponseType.bytes),
      onReceiveProgress: onProgress,
    );
    final encBytes = res.data is Uint8List
        ? res.data as Uint8List
        : Uint8List.fromList(res.data!);
    ConnectivityStatus.instance.offline.value = false;
    unawaited(LocalCache.instance.putBlob(assetId, variant, encBytes));
    return VaultCrypto.decryptBytes(vmk, encBytes);
  }

  /// Raw ENCRYPTED bytes [start, endInclusive] of an asset via an HTTP range
  /// request -- the building block for streaming video playback.
  Future<Uint8List> fetchEncryptedRange(
    String assetId,
    int start,
    int endInclusive,
  ) async {
    final res = await _dio.get<List<int>>(
      '/media/$assetId/raw',
      options: _transferOptions.copyWith(
        responseType: ResponseType.bytes,
        headers: {'Range': 'bytes=$start-$endInclusive'},
      ),
    );
    final data = res.data is Uint8List
        ? res.data as Uint8List
        : Uint8List.fromList(res.data!);
    if (res.statusCode == 206) return data;
    // Server ignored the Range header and sent everything -- slice it.
    final end = endInclusive + 1 > data.length ? data.length : endInclusive + 1;
    return Uint8List.sublistView(data, start, end);
  }

  /// Old single-blob videos that haven't been converted to the streamable
  /// format yet: [(id, encryptedSize)].
  Future<List<(String, int)>> listLegacyVideos() async {
    final res = await _dio.get('/media/legacy-videos');
    return (res.data as List)
        .map((e) => (e['id'] as String, (e['size_bytes'] as num).toInt()))
        .toList();
  }

  /// Uploads the chunk-encrypted replacement for an old video. The server
  /// keeps the old object too (never deletes media).
  Future<void> replaceWithChunked(
    String assetId,
    Uint8List encChunked, {
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(encChunked, filename: 'blob.enc'),
    });
    await _dio.put(
      '/media/$assetId/raw',
      data: form,
      options: _transferOptions,
      onSendProgress: onSendProgress,
    );
  }
}
