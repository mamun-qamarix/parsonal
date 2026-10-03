import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../../services/media_service.dart';
import '../crypto/chunked_crypto.dart';
import '../storage/local_cache.dart';

/// Streams a chunk-encrypted video to the video player without downloading
/// the whole file first (see DECISIONS.md).
///
/// The player gets an `http://127.0.0.1:<port>/<token>` URL. For each range
/// the player asks for, this fetches only the encrypted chunks covering it
/// (from the on-disk chunk cache when already seen, otherwise via an HTTP
/// range request to our server), verifies + decrypts each chunk (AES-GCM,
/// every chunk authenticated on its own -- nothing unverified is ever
/// played), and writes the plaintext back.
///
/// Security: bound to the loopback interface only, and each open video gets
/// a fresh unguessable 128-bit token that stops working as soon as the
/// player closes. Decrypted bytes only ever live in memory; only ciphertext
/// chunks are written to the cache.
class VideoStreamServer {
  VideoStreamServer._();
  static final instance = VideoStreamServer._();

  // Chunks fetched + decrypted per round trip / isolate hop.
  static const _batchChunks = 4;

  HttpServer? _server;
  final Map<String, _Source> _sources = {};
  final _random = Random.secure();

  /// Returns a playable URL for [assetId], or null if the asset is in the
  /// old single-blob format (the caller then falls back to downloading it
  /// whole).
  Future<Uri?> open(Uint8List vmk, String assetId) async {
    var headerBytes = await LocalCache.instance.getBlob(assetId, 'shdr');
    if (headerBytes == null) {
      headerBytes = await MediaService().fetchEncryptedRange(
        assetId,
        0,
        ChunkedCrypto.headerLength - 1,
      );
      if (!ChunkedCrypto.isChunked(headerBytes)) return null;
      await LocalCache.instance.putBlob(assetId, 'shdr', headerBytes);
    }
    final header = ChunkedHeader.parse(headerBytes);
    final keyBytes = await ChunkedCrypto.deriveKeyBytes(vmk, header.salt);

    var server = _server;
    if (server == null) {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(_handle);
      _server = server;
    }
    final token = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _sources[token] = _Source(assetId, header, keyBytes);
    return Uri.parse('http://127.0.0.1:${server.port}/$token.mp4');
  }

  void close(Uri uri) {
    final token = uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last.replaceAll('.mp4', '');
    _sources.remove(token);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final seg = req.uri.pathSegments;
    final source = seg.isEmpty
        ? null
        : _sources[seg.last.replaceAll('.mp4', '')];
    if (source == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final total = source.header.plainSize;
    var start = 0;
    var end = total - 1;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        final a = m.group(1)!, b = m.group(2)!;
        if (a.isEmpty && b.isNotEmpty) {
          start = max(total - int.parse(b), 0);
        } else {
          start = int.tryParse(a) ?? 0;
          if (b.isNotEmpty) end = min(int.parse(b), total - 1);
        }
      }
      if (start > end || start >= total) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
    res.headers
      ..contentType = ContentType('video', 'mp4')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    try {
      final cs = source.header.chunkSize;
      final first = start ~/ cs;
      final last = end ~/ cs;
      for (var i = first; i <= last; i += _batchChunks) {
        if (!_sources.containsValue(source)) break; // player closed
        final upTo = min(i + _batchChunks - 1, last);
        final plain = await source.decryptChunks(i, upTo);
        for (var c = i; c <= upTo; c++) {
          final data = plain[c - i];
          final chunkStart = c * cs;
          final from = max(start - chunkStart, 0);
          final to = min(end - chunkStart + 1, data.length);
          res.add(Uint8List.sublistView(data, from, to));
        }
        await res.flush(); // back-pressure: don't race ahead of the player
      }
    } catch (_) {
      // Player seeked/closed the connection, or a chunk failed to fetch or
      // verify -- either way stop sending; the player will retry/re-request.
    }
    try {
      await res.close();
    } catch (_) {}
  }
}

class _Source {
  final String assetId;
  final ChunkedHeader header;
  final Uint8List keyBytes;
  _Source(this.assetId, this.header, this.keyBytes);

  /// Encrypted chunks [first, last] -> decrypted, verified plaintext.
  Future<List<Uint8List>> decryptChunks(int first, int last) async {
    final enc = <int, Uint8List>{};
    var missingFrom = -1;
    for (var i = first; i <= last; i++) {
      final cached = await LocalCache.instance.getBlob(assetId, 'c$i');
      if (cached != null) {
        enc[i] = cached;
      } else if (missingFrom < 0) {
        missingFrom = i;
      }
    }
    if (missingFrom >= 0) {
      // One range request covering every chunk from the first missing one.
      final from = header.encOffset(missingFrom);
      final to = header.encOffset(last) + header.encLength(last) - 1;
      final bytes = await MediaService().fetchEncryptedRange(assetId, from, to);
      for (var i = missingFrom; i <= last; i++) {
        if (enc.containsKey(i)) continue;
        final off = header.encOffset(i) - from;
        final chunk = Uint8List.fromList(
          Uint8List.sublistView(bytes, off, off + header.encLength(i)),
        );
        enc[i] = chunk;
        // Ciphertext only -- same as what the server stores.
        LocalCache.instance.putBlob(assetId, 'c$i', chunk);
      }
    }
    final key = keyBytes;
    final lastIndex = header.chunkCount - 1;
    final jobs = [for (var i = first; i <= last; i++) (i, enc[i]!)];
    // AES-GCM in pure Dart is CPU-heavy: do it off the UI thread.
    return Isolate.run(() async {
      final out = <Uint8List>[];
      for (final (i, c) in jobs) {
        out.add(await ChunkedCrypto.decryptChunk(key, c, i, i == lastIndex));
      }
      return out;
    });
  }
}
